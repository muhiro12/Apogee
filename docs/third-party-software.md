# Third-party software

Apogee has no license grant for its original source code. This inventory does
not license Apogee under any dependency's terms. Each dependency retains its
own license and notices.

## Swift package dependencies

The following inventory describes the versions in the root `Package.resolved`.
SwiftPM downloads these packages separately; their sources are not vendored in
Apogee's source releases. Follow the linked license and notice files for the
versions actually resolved when redistributing any dependency or linked binary.

| Package | Resolved version | License | Notices |
| --- | --- | --- | --- |
| Swift Argument Parser | 1.8.2 | [Apache 2.0 with Runtime Library Exception](https://github.com/apple/swift-argument-parser/blob/1.8.2/LICENSE.txt) | Source file notices |
| Swift Crypto | 3.15.1 | [Apache 2.0](https://github.com/apple/swift-crypto/blob/3.15.1/LICENSE.txt) | [NOTICE.txt](https://github.com/apple/swift-crypto/blob/3.15.1/NOTICE.txt) |
| Swift ASN.1 | 1.7.1 | [Apache 2.0](https://github.com/apple/swift-asn1/blob/1.7.1/LICENSE.txt) | [NOTICE.txt](https://github.com/apple/swift-asn1/blob/1.7.1/NOTICE.txt) |
| Swift Collections | 1.6.0 | [Apache 2.0 with Runtime Library Exception](https://github.com/apple/swift-collections/blob/1.6.0/LICENSE.txt) | Source file notices |
| Swift HTTP Types | 1.6.0 | [Apache 2.0](https://github.com/apple/swift-http-types/blob/1.6.0/LICENSE.txt) | [NOTICE.txt](https://github.com/apple/swift-http-types/blob/1.6.0/NOTICE.txt) |
| Swift OpenAPI Runtime | 1.12.0 | [Apache 2.0](https://github.com/apple/swift-openapi-runtime/blob/1.12.0/LICENSE.txt) | [NOTICE.txt](https://github.com/apple/swift-openapi-runtime/blob/1.12.0/NOTICE.txt) |
| Swift OpenAPI URLSession | 1.3.1 | [Apache 2.0](https://github.com/apple/swift-openapi-urlsession/blob/1.3.1/LICENSE.txt) | [NOTICE.txt](https://github.com/apple/swift-openapi-urlsession/blob/1.3.1/NOTICE.txt) |

Apogee uses Swift Crypto's `Crypto` product, which uses Apple's CryptoKit on
the supported macOS platform. Swift Crypto also contains BoringSSL sources for
other configurations; do not assume that every file in that upstream package
has the same license when redistributing its sources or changing platforms.

## Code generation

The maintainer workflow uses
[Swift OpenAPI Generator](https://github.com/apple/swift-openapi-generator),
under [Apache 2.0](https://github.com/apple/swift-openapi-generator/blob/1.12.2/LICENSE.txt)
with its own [notices](https://github.com/apple/swift-openapi-generator/blob/1.12.2/NOTICE.txt).
The generator is downloaded as a maintainer tool and is not distributed as part
of Apogee's executable. Generated files identify their generator in the header.
Apple's App Store Connect OpenAPI document is downloaded locally and is not
included in the repository. See [OpenAPI generation](openapi-generation.md).

## Distribution

GitHub Releases currently distribute Apogee source archives only. Before adding
compiled executable assets, include the applicable third-party license texts
and attribution notices in the downloadable distribution. Links in this
inventory alone are not a replacement for those notices. Review this inventory
when dependencies, resolved versions, or distributed artifacts change.
