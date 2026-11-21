"""草图裁图小工具（备用）

用途：把讨论中收到的手绘草图按区域裁出来放大，方便核对识别。
当前环境限制：本机沙箱不允许命令行进程往工作区写文件，
所以这个脚本目前只能读到图、写不出图（PermissionError）。
换成可写目录后即可正常使用。

用法：
    python _crop.py <原图路径> <输出目录>

区域坐标在 regions 里改，格式 (name, (left, top, right, bottom))。
"""
import os
import sys

from PIL import Image

REGIONS = [
    ("2a-材料来源", (0, 0, 780, 290)),
    ("2b-军事与升级", (0, 230, 650, 770)),
    ("2c-司南四向", (800, 320, 1430, 730)),
    ("2d-灯火档位", (740, 620, 1130, 1010)),
    ("2e-灯火与研究点", (0, 700, 820, 1130)),
    ("2f-民众意愿", (1230, 950, 1920, 1310)),
]


def crop_all(src: str, out_dir: str) -> None:
    os.makedirs(out_dir, exist_ok=True)
    im = Image.open(src)
    print("source size:", im.size)
    for name, box in REGIONS:
        c = im.crop(box)
        c = c.resize((c.width * 2, c.height * 2), Image.LANCZOS)
        path = os.path.join(out_dir, name + ".png")
        c.save(path)
        print("wrote", path)


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print(__doc__)
        sys.exit(1)
    crop_all(sys.argv[1], sys.argv[2])
