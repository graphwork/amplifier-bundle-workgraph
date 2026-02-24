---
bundle:
  name: workgraph
  version: 0.2.0
  description: "Workgraph integration for Amplifier -- dependency-aware task graph coordination"
includes:
  - bundle: git+https://github.com/microsoft/amplifier-foundation@main
  - bundle: workgraph:behaviors/workgraph
hooks:
  - module: hook-shell
    source: git+https://github.com/microsoft/amplifier-module-hook-shell@main
    config:
      enabled: true
      timeout: 30
      allow_blocking: true
---

@workgraph:context/workgraph-guide.md
