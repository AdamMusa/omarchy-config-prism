# Compiled QML provenance

Omarchy UI generated this package's native Qt module from the tree-shaken Zui and
Omarchy host QML graph. Generated QML source contents were discarded after AOT compilation.

- Format: `qt-aot-qml-module` version 1
- Qt: `6.11.2`
- Module: `OmarchyUI.Bundles.B900779379ff3c86438fd`
- Source fingerprint: `900779379ff3c86438fd510b65632b7c6aa6c916fa94c7fa8819f80b5e907032`

## Artifacts

- `OmarchyUI/Bundles/B900779379ff3c86438fd/libomarchy_ui_bundle_b900779379ff3c86438fd.so` — `ab6129c0e7d877d598c7d194e34e1f317a87f965dba4e88cb97df8ad401e6c13`
- `OmarchyUI/Bundles/B900779379ff3c86438fd/libomarchy_ui_bundle_b900779379ff3c86438fdplugin.so` — `2a3f073c6691ac400c50130a6253eb4317f28603913fd1aba02e7758203375d7`

Verify the packaged libraries from the plugin directory:

```bash
sha256sum --check omarchy-ui-qml-bundle.sha256
```

`App.qml`, `Service.qml`, `Panel.qml`, and `BarWidget.qml` are the minimal loader shims
required by Omarchy's file-based entry-point contract. Application UI lives in the compiled
module recorded by `omarchy-ui-qml-bundle.json`.
