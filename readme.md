# Digest Builder

Create a one-file, Markdown “digest” of any Delphi / multi-language code-base – complete with optional directory tree, code blocks tagged for syntax highlighting, and super-lean *.pas* interface-only mode for feeding Large-Language-Models (token-savers unite ✂️).

---

## ✨ Features
* **Point-&-Shoot GUI** – choose a source folder, file-mask(s), and go.
* **Project presets** – save, reload, and tweak multiple “digest jobs”.
* **Interface-only mode** – strips implementation + boilerplate comments using a fast two-stage tokenizer (`PasUnitInterfaceCleaner.pas`).
* **Directory tree** – pretty ASCII tree honouring `.gitignore` + auto-filtered temp files.
* **Language tagging** – automatic Markdown code-fence language based on file extension (customisable in INI).
* **Clipboard ready** – optional auto-copy path of generated file.
* **Single-file output** – UTF-8 Markdown saved to *Output\<ProjectName>.md*.

---

## Building
1. Delphi 12 (Athens) or newer.  
2. Third-party dependencies:  
   * **JVCL** – for `TJvDirectoryEdit`.  
   * **MaxLogicFoundation** – for `autoFree.pas` & helpers.  

