"""Generate original ambience and interaction sounds for virtual drinking."""

from array import array
from pathlib import Path
import math
import random
import wave


SAMPLE_RATE = 16000
DURATION = 12
LENGTH = SAMPLE_RATE * DURATION
OUTPUT = Path(__file__).resolve().parents[1] / "assets" / "virtual_drinking" / "audio"


def make_samples(kind: str) -> list[float]:
    rng = random.Random(4102 if kind == "rain_window" else 9011)
    samples = []
    low = 0.0
    drops = [rng.randrange(LENGTH) for _ in range(230)] if kind == "rain_window" else []
    for index in range(LENGTH):
        t = index / SAMPLE_RATE
        noise = rng.uniform(-1, 1)
        low = low * (0.997 if kind == "ocean_waves" else 0.94) + noise * (
            0.003 if kind == "ocean_waves" else 0.06
        )
        if kind == "ocean_waves":
            envelope = 0.32 + 0.3 * (1 + math.sin(2 * math.pi * t / 5.8)) / 2
            sample = (low * 2.4 + noise * 0.08) * envelope
        else:
            sample = noise * 0.115 + low * 0.36
        samples.append(sample)

    if kind == "rain_window":
        for position in drops:
            for offset in range(96):
                target = (position + offset) % LENGTH
                decay = math.exp(-offset / 23)
                samples[target] += 0.12 * decay * math.sin(offset * 1.1)

    # Crossfade the tail into the beginning to keep the loop edge quiet.
    fade = SAMPLE_RATE // 2
    for index in range(fade):
        mix = index / fade
        samples[LENGTH - fade + index] = (
            samples[LENGTH - fade + index] * (1 - mix) + samples[index] * mix
        )
    return samples


def make_effect(kind: str) -> list[float]:
    length = int(SAMPLE_RATE * (0.42 if kind.startswith("ice") else 0.26))
    rng = random.Random(sum(ord(letter) for letter in kind))
    output = []
    for index in range(length):
        t = index / SAMPLE_RATE
        envelope = math.sin(math.pi * index / length) ** 2
        if kind.startswith("ice"):
            pitch = 920 if kind == "ice_drop" else 1540
            sound = math.sin(2 * math.pi * pitch * t) * math.exp(-t * 14)
            sound += rng.uniform(-1, 1) * (0.16 if kind == "ice_crush" else 0.07)
        else:
            pitch = 420 if kind == "sip_water" else 310
            sound = math.sin(2 * math.pi * (pitch - 60 * t) * t) * 0.28
            sound += rng.uniform(-1, 1) * 0.12
        output.append(sound * envelope)
    return output


def write_wave(path: Path, samples: list[float]) -> None:
    frames = array("h", [
        max(-32768, min(32767, round(sample * 23000)))
        for sample in samples
    ])
    with wave.open(str(path), "wb") as audio:
        audio.setnchannels(1)
        audio.setsampwidth(2)
        audio.setframerate(SAMPLE_RATE)
        audio.writeframes(frames.tobytes())


def main() -> None:
    OUTPUT.mkdir(parents=True, exist_ok=True)
    for kind in ("rain_window", "ocean_waves"):
        write_wave(OUTPUT / f"{kind}.wav", make_samples(kind))
    for kind in ("sip_soft", "sip_water", "ice_drop", "ice_crush"):
        write_wave(OUTPUT / f"{kind}.wav", make_effect(kind))


if __name__ == "__main__":
    main()
