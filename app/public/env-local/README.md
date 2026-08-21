# Local env maps (not in git)

Tone-mapped LDR versions of the Greyscalegorilla **Pro Studios Metal** HDRIs
(`metal-NNN.jpg`, 001–045). The GSG EULA forbids redistribution, and this repo
is public — so these stay local, same policy as `flip/app/public/hdri-local/`.

To regenerate on a new machine (source of truth is flip's local HDR set):

```sh
cd <this repo>
for f in ../flip/app/public/hdri-local/metal-*.hdr; do
  b=$(basename "$f" _2k.hdr)
  node scripts/hdr-to-env.js "$f" /tmp/$b.bmp 1024
  sips -s format jpeg -s formatOptions 82 /tmp/$b.bmp --out "app/public/env-local/$b.jpg"
done
```

The committed manifest (`src/data/env-presets.ts`) lists them; on a machine
without the files their thumbnails simply hide (img onerror).

The two maps in `../env/` (brown-studio, neon-studio) are Poly Haven CC0 and
ARE committed.
