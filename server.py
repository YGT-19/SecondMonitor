import asyncio
import json
import socket
import threading
import time
from io import BytesIO

import mss
import pyautogui
import websockets
from PIL import Image

# pyautogui'nin ekranın köşesine gidince güvenlik durdurması özelliğini kapat
pyautogui.FAILSAFE = False
# pyautogui her komuttan sonra otomatik bekleme süresini kaldır (gecikmeyi azaltır)
pyautogui.PAUSE = 0

SCREEN_W, SCREEN_H = pyautogui.size()

# --- AYARLANABİLİR PERFORMANS PARAMETRELERİ -------------------------------
# Telefondaki Ayarlar sayfasından gönderilen "config" mesajıyla canlı
# değiştirilir. Buradakiler, telefon hiç ayar göndermezse kullanılacak
# varsayılan (başlangıç) değerlerdir.
class ServerConfig:
    quality = 65     # 1-100, düşük = daha hızlı/az veri
    scale = 0.8      # Yakalanan görüntüyü bu oranda küçült
    fps = 24         # Üst sınır - donanım yetişemezse otomatik düşer


config = ServerConfig()
# ---------------------------------------------------------------------------

try:
    RESAMPLE = Image.Resampling.LANCZOS   # Pillow >= 9.1
except AttributeError:
    RESAMPLE = Image.LANCZOS              # Eski Pillow sürümleri

_thread_local = threading.local()


def _get_sct():
    """Her thread kendi mss örneğini kullanmalı (mss thread-safe değildir)."""
    if not hasattr(_thread_local, "sct"):
        _thread_local.sct = mss.mss()
    return _thread_local.sct


class FrameBuffer:
    """Yakalama thread'i ile asyncio gönderim görevi arasında kilitli ve
    olay (event) tabanlı basit bir köprü. Yakalama hızı ile gönderim hızı
    birbirini BLOKE ETMEDEN, bağımsız çalışabilsin diye kullanılır."""

    def __init__(self, loop: asyncio.AbstractEventLoop):
        self._lock = threading.Lock()
        self._data = None
        self._loop = loop
        self._event = asyncio.Event()

    def publish(self, data: bytes) -> None:
        with self._lock:
            self._data = data
        self._loop.call_soon_threadsafe(self._event.set)

    def take(self):
        with self._lock:
            data = self._data
            self._data = None
        return data

    async def wait_for_next(self):
        await self._event.wait()
        self._event.clear()


def _capture_loop(frame_buffer: FrameBuffer, stop_event: threading.Event) -> None:
    """Ayrı, gerçek bir thread'de SÜREKLİ çalışır. Donanımın izin verdiği
    en yüksek hızda ekranı yakalar + küçültür + WebP'e sıkıştırır.
    Ağ gönderimi bu döngüyü beklemek zorunda değildir; her zaman en GÜNCEL
    kareyi alır (henüz gönderilmemiş eski kareler otomatik atlanır)."""
    sct = _get_sct()
    monitor = sct.monitors[1]  # 1 = ana ekran (tüm monitörler için 0 kullanılabilir)

    while not stop_event.is_set():
        start = time.time()

        shot = sct.grab(monitor)
        img = Image.frombytes("RGB", shot.size, shot.bgra, "raw", "BGRX")

        new_size = (int(shot.width * config.scale), int(shot.height * config.scale))
        img = img.resize(new_size, RESAMPLE)

        buf = BytesIO()
        # WebP, aynı görsel kalitede JPEG'den genelde %20-35 daha küçük dosya
        # üretir -> aynı ağ hızında daha yüksek kalite VEYA daha yüksek FPS.
        # method: 0=hızlı/büyük dosya .. 6=yavaş/küçük dosya. CPU yetersiz
        # kalırsa (FPS düşüyorsa) bunu 2-3'e indirebilirsin.
        img.save(buf, format="WEBP", quality=config.quality, method=4)
        frame_buffer.publish(buf.getvalue())

        elapsed = time.time() - start
        target_interval = 1 / max(1, config.fps)
        sleep_for = target_interval - elapsed
        if sleep_for > 0:
            time.sleep(sleep_for)
        # CPU hedef FPS'i karşılayamıyorsa sleep atlanır; thread bir sonraki
        # kareyi hemen yakalamaya başlar (mümkün olan en yüksek hızda devam
        # eder, görüntü her zaman mevcut en güncel haliyle gösterilir).


async def capture_and_send(websocket, frame_buffer: FrameBuffer) -> None:
    """En güncel kare hazır olur olmaz hemen gönderir (bekleme/sıralı
    yoklama değil, olay tabanlı) - yakalama ile gönderim arasında
    gereksiz gecikme oluşmaz."""
    while True:
        await frame_buffer.wait_for_next()
        data = frame_buffer.take()
        if data is None:
            continue
        try:
            await websocket.send(data)

            cx, cy = pyautogui.position()
            await websocket.send(json.dumps({
                "type": "cursor",
                "x": cx / SCREEN_W,
                "y": cy / SCREEN_H,
            }))
        except websockets.exceptions.ConnectionClosed:
            break


def to_screen_coords(x_norm, y_norm):
    """Telefondan gelen 0-1 arası normalize koordinatı gerçek ekran pikseline çevirir."""
    x = max(0, min(SCREEN_W - 1, int(x_norm * SCREEN_W)))
    y = max(0, min(SCREEN_H - 1, int(y_norm * SCREEN_H)))
    return x, y


async def handle_control_messages(websocket):
    """Telefondan gelen JSON kontrol mesajlarını okuyup fare/klavyeye uygular."""
    async for message in websocket:
        if isinstance(message, (bytes, bytearray)):
            continue  # binary mesaj bu yönde beklenmiyor

        try:
            data = json.loads(message)
        except json.JSONDecodeError:
            continue

        msg_type = data.get("type")

        if msg_type in ("move", "tap", "double_tap", "right_tap",
                         "drag_start", "drag_move", "drag_end"):
            x, y = to_screen_coords(data.get("x", 0), data.get("y", 0))

        if msg_type == "move":
            pyautogui.moveTo(x, y)
        elif msg_type == "tap":
            pyautogui.click(x, y)
        elif msg_type == "double_tap":
            pyautogui.doubleClick(x, y)
        elif msg_type == "right_tap":
            pyautogui.click(x, y, button="right")
        elif msg_type == "drag_start":
            pyautogui.moveTo(x, y)
            pyautogui.mouseDown()
        elif msg_type == "drag_move":
            pyautogui.moveTo(x, y)
        elif msg_type == "drag_end":
            pyautogui.mouseUp()
        elif msg_type == "scroll":
            dy = data.get("dy", 0)
            # Pozitif değer yukarı, negatif değer aşağı kaydırır (pyautogui kuralı).
            # Yön ters geliyorsa buradaki işareti (-) ile değiştirebilirsin.
            pyautogui.scroll(int(dy))
        elif msg_type == "key":
            key = data.get("key")
            if key:
                special_keys = {
                    "backspace", "enter", "tab", "space", "esc",
                    "delete", "up", "down", "left", "right", "home", "end",
                }
                if key in special_keys:
                    pyautogui.press(key)
                else:
                    # Tek karakterler (harf/sayı/işaret) - büyük harf ve
                    # bazı özel karakterleri de doğru basan write() kullanılır.
                    pyautogui.write(key)
        elif msg_type == "config":
            # Telefondaki Ayarlar sayfasından gelen görüntü kalitesi ayarları.
            if "quality" in data:
                config.quality = max(10, min(95, int(data["quality"])))
            if "scale" in data:
                config.scale = max(0.2, min(1.0, float(data["scale"])))
            if "fps" in data:
                config.fps = max(5, min(30, int(data["fps"])))
            print(f"Ayarlar güncellendi -> kalite={config.quality}, "
                  f"ölçek={config.scale}, fps={config.fps}")


async def handler(websocket):
    print("Telefon bağlandı:", websocket.remote_address)

    # Küçük kontrol mesajlarının (tap, drag vb.) ağda bekletilmeden anında
    # gönderilmesi için Nagle algoritmasını kapatıyoruz. Bazı websockets
    # sürümlerinde bu özellik bulunmayabilir, o yüzden hataya karşı korumalı.
    try:
        sock = websocket.transport.get_extra_info("socket")
        if sock is not None:
            sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
    except AttributeError:
        pass

    # Telefonun doğru en/boy oranını hesaplayabilmesi için gerçek ekran
    # çözünürlüğünü bağlantı kurulur kurulmaz bir JSON mesajıyla bildiriyoruz.
    await websocket.send(json.dumps({
        "type": "info",
        "width": SCREEN_W,
        "height": SCREEN_H,
    }))

    # Ekran yakalamayı ayrı, gerçek bir thread'de başlatıyoruz. Bu thread
    # bağlantı süresince sürekli çalışır; asyncio döngüsünü asla bloke etmez.
    loop = asyncio.get_running_loop()
    frame_buffer = FrameBuffer(loop)
    stop_capture = threading.Event()
    capture_thread = threading.Thread(
        target=_capture_loop, args=(frame_buffer, stop_capture), daemon=True
    )
    capture_thread.start()

    send_task = asyncio.create_task(capture_and_send(websocket, frame_buffer))
    recv_task = asyncio.create_task(handle_control_messages(websocket))
    try:
        await asyncio.gather(send_task, recv_task)
    except websockets.exceptions.ConnectionClosed:
        pass
    finally:
        stop_capture.set()
        send_task.cancel()
        recv_task.cancel()
        capture_thread.join(timeout=1.0)
        print("Bağlantı kapandı.")


async def main():
    print(f"Ekran çözünürlüğü: {SCREEN_W}x{SCREEN_H}")
    async with websockets.serve(handler, "0.0.0.0", 8765, max_size=None):
        print("Sunucu çalışıyor -> ws://<bilgisayar-ip>:8765")
        print("Bağlanmak için telefon ve bilgisayarın aynı WiFi ağında olduğundan emin ol.")
        await asyncio.Future()  # sonsuza kadar çalış


if __name__ == "__main__":
    asyncio.run(main())