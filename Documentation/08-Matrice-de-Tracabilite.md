# 08 — Matrice de traçabilité

Table exhaustive des fonctions, procédures, types et constantes du code métier à
réimplémenter, avec la cible Swift. Les éléments internes (fonctions imbriquées) sont
indentés sous leur fonction englobante.

Légende cible :
- **Core** = `DeskewCore`
- **IO** = `DeskewImageIO`
- **CLI** = `DeskewCLI`
- **—** = ne pas porter (remplacé / hors périmètre / test)

---

## 1. `RotationDetector.pas`

| Pascal | Type | Cible Swift | Notes |
| ------ | ---- | ----------- | ----- |
| `TCalcSkewAngleStats` | record | `SkewStats` | Core |
| `CalcRotationAngle` | function | `HoughSkewDetector.rotationAngle` | Core |
| └ `IsPixelBlack` | function | *(inline)* | `< Threshold` |
| └ `GetFinalAngle` | function | *(inline)* | `AlphaStart + i·AngleStep` |
| └ `CalcLines` | procedure | `accumulate` | cœur du vote |
| └ `CalcHoughTransform` | procedure | `collectVotes` | filtre ligne de base |
| └ `GetBestLines` | function | `bestLines` | top 20, tri insertion |

---

## 2. `ImageUtils.pas`

| Pascal | Type | Cible Swift | Notes |
| ------ | ---- | ----------- | ----- |
| `TResamplingFilter` | enum | `ResamplingFilter` | Core |
| `SupportedRotationFormats` | const | *(contrainte de type)* | Core |
| `IsImageDataEqual` | function | `PixelImage.isEqual(to:)` | tests |
| `OtsuThresholding` | function | `Otsu.threshold` | Core |
| `BinarizeImage` | procedure | `Binarization.binarize` | Core |
| `RotateImage` | procedure | `ImageRotation.rotate` (surcharges) | Core |
| └ `TBufferEntry` | record | `Accum4` (SIMD4\<Float\>) | canaux |
| └ `FastFloor` | function | `floor`/helper | voir parité |
| └ `FastCeil` | function | `ceil`/helper | voir parité |
| └ `GetPixelColor24` | function | `sampleRGB` | bornes → fond |
| └ `GetPixelColor8` | function | `sampleGray` | bornes → fond |
| └ `GetPixelColor32` | function | `sampleRGBA` | bornes → fond |
| └ `GetBilinearPixelCoords` | procedure | `bilinearCoords` | |
| └ `InterpolateBytes` | function | `interpolateByte` | |
| └ `Bilinear24` | function | `bilinearRGB` | |
| └ `Bilinear8` | function | `bilinearGray` | |
| └ `Bilinear32` | function | `bilinearRGBA` | |
| └ `PrecomputeFilterWeights` | procedure | `FilterKernel.makeTable` | table 32 pas |
| └ `FilterPixel` | function | `applyKernel` | convolution + bords |
| └ `TryMultipleOf90Rotation` | function | `ImageRotation.rotate90` | |
| └ `CalcSourceCoordinates` | procedure | `sourceCoordinates` | mapping inverse |

---

## 3. `Utils.pas`

| Pascal | Type | Cible Swift | Notes |
| ------ | ---- | ----------- | ----- |
| `TSizeUnit` | enum | `SizeUnit` | Core |
| `NullRect` / `NullFloatRect` | const | `.zero` | Core |
| `MakeScaledRect` | function | `FloatRect.scaled(width:height:)` | privé |
| `IsRectNull` | function | `IntRect.isNull` | |
| `IsFloatRectNull` | function | `FloatRect.isNull` | |
| `RectToStr` | function | `IntRect.description` (format `[l,t,r,b]`) | journal |
| `CalcRectInPixels` | function | `ContentRect.calcRectInPixels` | conversion unités |

---

## 4. `CmdLineOptions.pas`

| Pascal | Type | Cible Swift | Notes |
| ------ | ---- | ----------- | ----- |
| `DefaultThreshold` = 128 | const | `DeskewOptions.defaults` | |
| `DefaultMaxAngle` = 10 | const | idem | |
| `DefaultAngleStep` = 0.1 | const | idem | |
| `DefaultSkipAngle` = 0.01 | const | idem | |
| `TThresholdingMethod` | enum | `ThresholdingMethod` | |
| `TOperationalFlag(s)` | set | `cropToInput` / `detectOnly` | bool |
| `TCmdLineOptions.Create` | ctor | `DeskewOptions.init` | valeurs par défaut |
| `GetIsValid` | property | `DeskewOptions.isValid` | |
| `Reset` | procedure | `DeskewOptions.init` | |
| `CheckParam` | function | `DeskewOptions.parseOption` | cœur du parsing |
| └ `TryParseSizeRect` | function | `parseFloatRect` | 1/2/4 valeurs |
| └ `TryParseSizeUnit` | function | `SizeUnit.init(token:)` | `px\|%\|mm\|cm\|in` |
| `Parse` | function | `DeskewOptions.parse` | boucle d'arguments |
| `ParseCommandLine` | function | *(CLI)* | `CommandLine.arguments` |
| `CalcContentRectForImage` | function | `ContentRect.forImage` | marges vs rect |
| `TrySetTiffCompressionFromMetadata` | function | `Metadata.tiffCompression` | IO+Options |
| `OptionsToString` | function | `DeskewOptions.optionsDescription(commandLine:)` | journal |
| `EnsureTrailingPathDelimiter` | function | `FilePath.ensureTrailingDelimiter` | |
| `TiffCompressionOptionAsInput` | const | `TiffCompression.input` | |
| `TiffCompressionNames` | const | mapping énum | |
| `SizeUnitTokens` | const | `SizeUnit.rawValue` | |
| `FloatFmtSettings` | var | `Locale`-indépendant | parsing `.` décimal |

---

## 5. `MainUnit.pas`

| Pascal | Type | Cible Swift | Notes |
| ------ | ---- | ----------- | ----- |
| `SAppTitle`, `SAppHome` | const | `DeskewCLI.banner` | |
| `Options`, `InputImage`, `OutputImage` | var | état local CLI | |
| `WriteUsage` | procedure | `DeskewCommand.help` / `usageText` | |
| `ReportBadInput` | procedure | `DeskewCLI.fail` | `ERROR:` + exit 1 |
| `FormatNiceNumber` | function | `formattedNumber` | séparateurs |
| `WriteTiming` | procedure | `Logger.timing` | `µs` |
| `DoDeskew` | function | `Pipeline.run` | Core |
| └ `WriteDetectionStats` | procedure | `Logger.detectionStats` | |
| └ `EnsurePixelFormatForRotation` | procedure | `PixelConversion.ensureRotatable` | |
| └ `ChangeOutputFormatIfNeeded` | function | `Pipeline.changeOutputFormat` | |
| `RunDeskew` | procedure | `DeskewCommand.run` | CLI |
| └ `EnsureOutputLocation` | procedure | `createDirectory` | IO |
| └ `CopyFile` | procedure | `FileManager.copyItem` | IO |
| └ `SetImagingOutputOptions` | procedure | `ImageWriter.options` | IO |

---

## 6. Tests (`Tests/`)

| Pascal | Cible Swift | Notes |
| ------ | ----------- | ----- |
| `TDeskewTestCase` (+ assertions) | helpers XCTest | |
| `TTestImageUtils` | `OtsuTests`, `BinarizationTests` | |
| `TTestImageRotation` | `RotationTests` | |
| `TTestCmdLineOptions` | `OptionsParsingTests`, `GeometryTests` | |
| `TTestSkewDetection` | *(vide — rien à porter)* | remplacer par golden |
| `DeskewTestUtils.pas` | `TestSupport.swift` | |

---

## 7. API de la bibliothèque Imaging utilisée (à remplacer)

| Symbole Imaging | Usage | Remplacement Swift |
| --------------- | ----- | ------------------ |
| `TImageData` | image brute | types `GrayImage`/`RGBImage`/`RGBAImage` |
| `TColor24Rec`, `TColor32Rec`, `TColor32` | pixels | `RGB24`, `RGBA32` (layout B,G,R,A) |
| `PByteArray` | accès pixels | `UnsafeMutableBufferPointer<UInt8>` |
| `TRect`, `TFloatRect`, `TPoint` | géométrie | `IntRect`, `FloatRect`, `IntPoint` |
| `TSingleImage.Assign/Valid/Width/Height/Bits/ImageDataPointer/BoundsRect` | conteneur image | structures Swift |
| `TSingleImage.LoadFromFile/SaveToFile` | I/O | `DeskewImageIO` (ImageIO) |
| `TSingleImage.Format`, `.FormatInfo` | format | `PixelFormat` |
| `TSingleImage.Palette`, `.PaletteEntries` | palettes | conversion à l'import |
| `InitImage`, `NewImage`, `FreeImage` | allocation | initialiseurs / ARC |
| `GetImageFormatInfo` | Bpp, etc. | propriété `bytesPerPixel` |
| `RotateImageMul90` | rotation 90/180/270 | `ImageRotation.rotate90` |
| `CopyPixel` | copie n octets | `copyMemory` / affectation |
| `ClampToByte` | borne 0..255 | `clampToByte` |
| `IsFileFormatSupported` | validation CLI | `ImageLoader.canRead/canWrite` |
| `FindImageFileFormatByName` | détection TIFF | extension + UTI |
| `GetFileFormatCount/AtIndex` | liste usage | liste fixe |
| `GetFormatName` | affichage format | `PixelFormat.name` |
| `PaletteHasAlpha`, `PaletteIsGrayScale` | conversion | `Palette` helpers |
| `GlobalMetadata`, `TMetadata` | DPI, compression TIFF | `ResolutionInfo` + propriétés ImageIO |
| `SetOption(ImagingJpegQuality/TiffJpegQuality/JNGQuality/TiffCompression)` | options d'écriture | clés `CGImageDestination*` |
| `SamplingFilterFunctions`, `SamplingFilterRadii` | noyaux | `ResamplingKernels` |
| `sfCatmullRom`, `sfLanczos` | filtres | noyaux recodés |
| `GetFormatSettingsForFloats` | parsing `Float` | `Locale(identifier: "en_US_POSIX")` |
| `GetTimeMicroseconds` | timings | `DispatchTime` / `ContinuousClock` |
| `GetFileExt`, `GetFileName`, `GetFileDir` | chemins | `URL` |
| `Iff` | ternaire | `?:` |
| `TBaseTiffFileFormat` | détection TIFF | extension/UTI |
| `TiffCompressionOption*` | schémas TIFF | `enum TiffCompression` |

---

## 8. Fonctions non portées (hors périmètre)

| Élément | Raison |
| ------- | ------ |
| Interface graphique (`Gui/` Pascal) | retirée du dépôt (upstream uniquement) |
| `Imaging/JpegLib/*`, `Imaging/ZLib/*` | codecs remplacés par ImageIO |
| `Imaging/LibTiff/*` | remplacé par ImageIO pour TIFF |
| `Imaging/ImagingWic.pas`, `ImagingQuartz.pas` | spécifique plateforme, remplacé |
| Formats DDS / TGA / PPM / PGM / PAM / PFM / JNG / QOI / écriture PSD | non couverts par ImageIO (à décider en v2) |
| `deskew.dpr`, `deskew.dproj`, `deskew.lpi`, `*.groupproj` | fichiers projet Pascal |
| `Scripts/*.sh`, `Scripts/*.bat` | remplacés par SwiftPM / Makefile |
