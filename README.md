# Mon

macOS のアプリアイコンに、ビルド番号やブランチ名の帯バッジを合成する CLI です。既定は下端の水平な帯です。上端の帯と右上の斜めリボンも選べます。

- Pure Swift。画像処理の外部ライブラリは使いません。
- 実行時のシステム依存はありません。CoreGraphics / CoreText / ImageIO だけで描画します。
- 入力の Display P3 を sRGB に潰さず、ICC プロファイルを PNG に残します。
- 入力にアルファが無ければ、出力にもアルファを付けません。

PDF と SVG は未対応です。入力は ImageIO が読めるラスタ（PNG、JPEG、HEIC、TIFF など）で、出力は常に PNG です。

## インストール

```bash
brew tap novr/taps
brew install mon
```

## ビルド

```bash
swift build -c release
BIN="$(swift build -c release --show-bin-path)/Mon"
"$BIN" --help
```

SwiftPM のプロダクト名は `Mon` です。Homebrew とリリースアーカイブのコマンド名は `mon` です。

## 使い方

```text
-i, --input <path>       入力画像（必須）
-o, --output <path>      出力 PNG。省略時は入力が .png のときだけ上書き
-t, --title <string>     左（shield）または上段（band）。必須
-s, --subtitle <string>  右（shield）または下段（band）。省略すると shield は1区画
--color <hex>            右側（shield）または帯（band）の色。#RRGGBB または #RRGGBBAA（既定 #1E1E1ED9）
-p, --position <value>   top（上端） / bottom（下端） / ribbon（右上の斜めリボン。style は使わない）。既定 bottom
--style <value>          shield（左右2色。既定） / band（上下2段）
```

既定の `shield` は、`-s` があると左右2色、無いと `--color` の1区画です。2色のとき `--color` は右側だけに使い、左側は `#555555` で、不透明度だけ `--color` に合わせます。バッジの幅は文字幅の合計で、選んだ辺の中央に揃えます。上下2段は `--style band` です。`-p ribbon` は style を見ずに斜めリボンを描きます。

```bash
mon -i AppIcon.png -t DEV
mon -i AppIcon.png -t DEV -s "v1.2.0 (42)"
mon -i photo.jpg -o photo-badged.png -t MAIN --color "#C0392B"
mon -i AppIcon.png -t DEV -s "42" -p top
mon -i AppIcon.png -t DEV -s "v1.2.0 (42)" -p ribbon
```

入力が JPEG などのとき、`-o` を省略すると上書きせず終了します。`.png` 以外の出力拡張子は受け付けません。

## CI からリリースバイナリを使う

`MON_VERSION` は公開済みのタグに置き換えてください。`v0.1.0` は見本です。

```bash
MON_VERSION=v0.1.0
curl -fsSL -O "https://github.com/novr/Mon/releases/download/${MON_VERSION}/mon_${MON_VERSION#v}_darwin.tar.gz"
curl -fsSL -O "https://github.com/novr/Mon/releases/download/${MON_VERSION}/checksums.txt"
shasum -a 256 -c checksums.txt
tar -xzf "mon_${MON_VERSION#v}_darwin.tar.gz"
```

ブラウザで落としたバイナリには quarantine が付くことがあります。curl で取得したバイナリには付きません。

### Xcode Cloud

`ci_scripts/ci_post_clone.sh`:

```bash
#!/bin/bash
set -euo pipefail

if [[ "${CI_WORKFLOW:-}" == "Release" ]]; then
  exit 0
fi

MON_VERSION=v0.1.0
ASSET="mon_${MON_VERSION#v}_darwin.tar.gz"
BASE="https://github.com/novr/Mon/releases/download/${MON_VERSION}"
WORK="$(mktemp -d)"
curl -fsSL -o "${WORK}/${ASSET}" "${BASE}/${ASSET}"
curl -fsSL -o "${WORK}/checksums.txt" "${BASE}/checksums.txt"
(cd "${WORK}" && shasum -a 256 -c checksums.txt && tar -xzf "${ASSET}")

find "${CI_PRIMARY_REPOSITORY_PATH}/path/to/AppIcon.appiconset" -name '*.png' -print0 |
  while IFS= read -r -d '' icon; do
    "${WORK}/mon" -i "$icon" -t "${CI_BRANCH:-DEV}" -s "${CI_BUILD_NUMBER:-}"
  done
```

`chmod +x ci_scripts/ci_post_clone.sh` を忘れずに。

単一の 1024px アイコンなら `find` ではなく、その PNG を一つ渡せば足ります。

### GitHub Actions

```yaml
- name: Badge app icons
  shell: bash
  run: |
    set -euo pipefail
    MON_VERSION=v0.1.0
    curl -fsSL -O "https://github.com/novr/Mon/releases/download/${MON_VERSION}/mon_${MON_VERSION#v}_darwin.tar.gz"
    curl -fsSL -O "https://github.com/novr/Mon/releases/download/${MON_VERSION}/checksums.txt"
    shasum -a 256 -c checksums.txt
    tar -xzf "mon_${MON_VERSION#v}_darwin.tar.gz"
    find path/to/AppIcon.appiconset -name '*.png' -print0 |
      while IFS= read -r -d '' icon; do
        ./mon -i "$icon" -t "${GITHUB_REF_NAME}" -s "${GITHUB_RUN_NUMBER}"
      done
```

## ライセンス

MIT
