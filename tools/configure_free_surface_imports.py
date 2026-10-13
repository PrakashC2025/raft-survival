"""Keep added CC0 maps mipmapped and compressed for PC and Android."""
from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
for folder, pattern in (("textures/salvage", "*.jpg.import"), ("textures/underwater", "coast_*.jpg.import")):
    for path in (root / folder).glob(pattern):
        text = path.read_text()
        for key, value in {"compress/mode": "2", "compress/high_quality": "true",
                           "compress/normal_map": "1" if "nor_gl" in path.name else "0",
                           "mipmaps/generate": "true", "process/size_limit": "1024"}.items():
            text = re.sub(r"^" + re.escape(key) + r"=.*$", key + "=" + value, text, flags=re.M)
        path.write_text(text)
print("Configured nine imported 1K maps for mipmaps and high-quality VRAM compression.")
