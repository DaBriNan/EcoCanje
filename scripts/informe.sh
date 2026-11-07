#!/bin/bash
# Uso: scripts/informe.sh   — genera el expediente técnico: diagramas PNG, informe único en .docx (editable) y .pdf.
# Salida: docs/informe/salida/EcoCanje-expediente.{md,docx,pdf}. Herramientas en Docker fijadas por digest; PDF con LibreOffice.
set -euo pipefail
cd "$(dirname "$0")/.."
MMDC=docker.io/minlag/mermaid-cli:12.0.0@sha256:fa995339034aae7e5cd4f61482248b7f5c51be355b1a6f6eda11a2bbf8401f5f
PANDOC=docker.io/pandoc/core:3.11.0@sha256:62518bfb6833705dc90a1634d8d879299bd820b3f74ad3b32fba8b618452553a
OUT=docs/informe/salida; mkdir -p "$OUT"
dr() { docker run --rm -u "$(id -u):$(id -g)" -v "$PWD:/w" -w /w "$@"; }

echo "1. Diagramas (docs/diagramas/*.mmd -> .png)"
for f in docs/diagramas/*.mmd; do dr "$MMDC" -q -s 2 -b white -i "/w/$f" -o "/w/${f%.mmd}.png"; done

echo "2. Informe único (portada + D01..D10); rutas de imagen relativas a la raíz"
{ for f in docs/informe/00-portada.md docs/informe/D[0-9][0-9]-*.md; do cat "$f"; printf '\n\n\\newpage\n\n'; done; } \
  | sed 's#](\.\./diagramas/#](docs/diagramas/#g; s#](\.\./evidencias/#](docs/evidencias/#g' > "$OUT/EcoCanje-expediente.md"

echo "3. Bloques mermaid incrustados -> imágenes"
mkdir -p "$OUT/img"
dr "$MMDC" -q -s 2 -b white -e png -i "/w/$OUT/EcoCanje-expediente.md" -o "/w/$OUT/EcoCanje-expediente-render.md" -a "/w/$OUT/img"
sed -i "s#](/w/#](#g; s#](\./img/#]($OUT/img/#g" "$OUT/EcoCanje-expediente-render.md"

echo "4. DOCX editable (pandoc)"
dr "$PANDOC" "$OUT/EcoCanje-expediente-render.md" --from markdown+pipe_tables \
  --resource-path=.:docs/informe -o "$OUT/EcoCanje-expediente.docx"

echo "5. PDF (LibreOffice sin interfaz)"
soffice --headless --convert-to pdf --outdir "$OUT" "$OUT/EcoCanje-expediente.docx" >/dev/null 2>&1 \
  || libreoffice --headless --convert-to pdf --outdir "$OUT" "$OUT/EcoCanje-expediente.docx" >/dev/null
ls -la "$OUT"/EcoCanje-expediente.{docx,pdf}
