# Third-party notices

## Tokei upstream

This Windows adaptation reuses and adapts code and pricing data from [cclank/tokei](https://github.com/cclank/tokei), upstream revision `b3b9615ce8545edcc4f87a288f4de5ae165796fd`. The upstream README declares MIT. Copyright and license notices are retained in [LICENSE](LICENSE) and [UPSTREAM.md](UPSTREAM.md).

## Windows client and build dependencies

The versions below are pinned in `windows/requirements-build.txt` for reproducible builds. Qt for Python packages and Qt shared libraries are included in the Windows executable; Nuitka is used only while building.

| Component | Version | License / notice |
| --- | --- | --- |
| PySide6, Shiboken6, Qt for Python and Qt runtime modules | 6.11.2 | Qt for Python Community Edition licensing is described by Qt as LGPLv3/GPLv3. Qt for Python also contains components with their own licenses; see the [Qt for Python license inventory](https://doc.qt.io/qtforpython-6/licenses.html) and [Qt for Python licensing page](https://doc.qt.io/qtforpython-6/commercial/index.html). |
| keyring | 25.7.0 | MIT |
| psutil | 7.2.2 | BSD-3-Clause |
| Nuitka | 4.2.2 | GNU AGPLv3 with an exception for created binaries; see [Nuitka license and binary exception](https://nuitka.net/doc/download.html). Nuitka itself is a build-time dependency and is not bundled as a runtime package. |
| ordered-set | 4.1.0 | MIT; build-time dependency of Nuitka. |
| zstandard | 0.25.0 | BSD-3-Clause; build-time dependency of Nuitka. |

Qt for Python follows the same licensing model as Qt, with Community and Commercial distributions. Before redistributing a Windows executable, review the licenses for the Qt modules and third-party components actually included in that build, and provide the notices and corresponding materials required by those licenses. The exact Qt deployment behavior is documented in [pyside6-deploy](https://doc.qt.io/qtforpython-6/deployment/deployment-pyside6-deploy.html).

Python and its standard library are distributed under the PSF license; see the [Python license](https://docs.python.org/3/license.html). Transitive package versions are resolved from the pinned direct dependencies above. Recheck the package metadata and include applicable notices when updating dependency pins.
