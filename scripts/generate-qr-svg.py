import argparse
from pathlib import Path

import qrcode
from qrcode.image.svg import SvgPathImage


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate a local SVG QR code.")
    parser.add_argument("--text", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)

    qr = qrcode.QRCode(
        error_correction=qrcode.constants.ERROR_CORRECT_M,
        box_size=10,
        border=4,
    )
    qr.add_data(args.text)
    qr.make(fit=True)
    image = qr.make_image(image_factory=SvgPathImage)
    image.save(str(output))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
