//
//  main.swift
//  DeskewCLI
//
//  Travail dérivé de Deskew (MPL 2.0).
//

import Foundation
import DeskewCore
import DeskewImageIO

let appTitle = "Deskew 1.33 (2025-06-02) by Marek Mauder"
let appHome = "https://github.com/galfar/deskew\nhttps://galfar.vevb.net/deskew"

func writeUsage() {
    print("""
    Usage:
    deskew [-o output] [-a angle] [-b color] [..] input
        input:         Input image file

      Options:
        -o output:     Output image file name (default: prefixed input as png)
        -b color:      Background color in hex format RRGGBB|LL|AARRGGBB (default: black)
        -q filter:     Resampling filter used for rotations (default: linear
                       values: nearest|linear|cubic|lanczos)
        -a angle:      Maximal expected skew angle (both directions) in degrees (default: 10)

      Ext. options:
        -d angle:      Angle step during detection in degrees (default: 0.1)
        -t a|treshold: Auto threshold or value in 0..255 (default: auto)
        -m margins:    Skew detection only outside page margins
        -r rect:       Skew detection only in content rectangle
        -f format:     Force output pixel format (values: b1|g8|rgb24|rgba32)
        -p dpi:        Print resolution override
        -l angle:      Skip deskewing step if skew angle is smaller (default: 0.01)
        -g flags:      Operational flags: c - crop to input size, d - detect only
        -s info:       Info dump: s - stats, p - params, t - timings, w - save work image
        -c specs:      Output compression specs (jXX JPEG quality, tSCHEME TIFF scheme)
    """)
}

func reportBadInput(_ message: String, options: DeskewOptions, showUsage: Bool = true) -> Never {
    print("ERROR: " + message)
    if !options.errorMessage.isEmpty {
        print(options.errorMessage)
    }
    print("")
    if showUsage { writeUsage() }
    exit(1)
}

let arguments = Array(CommandLine.arguments.dropFirst())

print(appTitle)
print(appHome)
print("")

var options = DeskewOptions()
let parsed = options.parse(arguments)

if !parsed || !options.isValid {
    reportBadInput("Invalid parameters!", options: options)
}

if options.showParams {
    print(options.optionsDescription(commandLine: arguments))
}

let inputName = options.inputFileName!
let outputName = options.outputFileName!

if !ImageLoader.canRead(inputName) {
    reportBadInput("Input file format not supported: " + inputName, options: options)
}
if !ImageWriter.canWrite(outputName) {
    reportBadInput("Output file format not supported: " + outputName, options: options)
}

let loaded: LoadedImage
var loadWatch = Stopwatch()
do {
    loaded = try ImageLoader.load(path: inputName)
} catch {
    reportBadInput("Loaded input image is not valid: " + inputName, options: options, showUsage: false)
}

if options.showTimings {
    print(loadWatch.line("Load input file"))
}

print("Preparing input image (\(FilePath.fileName(inputName)) [\(loaded.width)x\(loaded.height)/\(loaded.format.name)]) ...")

let result: PipelineResult
do {
    result = try Pipeline.run(input: loaded.image, resolution: loaded.resolution,
                              options: options, inputTiffCompression: loaded.tiffCompression,
                              inputFormat: loaded.format)
} catch {
    print("")
    print(error)
    exit(1)
}

for line in result.log {
    print(line)
}

if options.saveWorkImage, let workImage = result.workImage {
    let workPath = FilePath.ensureTrailingDelimiter(FilePath.fileDir(outputName)) + "work-image.png"
    let workOptions = ImageWriteOptions(resolution: loaded.resolution)
    try? ImageWriter.save(.gray(workImage), to: workPath, options: workOptions)
}

if options.detectOnly {
    print("Done!")
    exit(0)
}

guard let outputImage = result.outputImage else {
    print("Done!")
    exit(0)
}

print("Saving output (\(FilePath.expandFileName(outputName)) [\(outputImage.width)x\(outputImage.height)/\(result.resolvedOutputFormat?.name ?? outputImage.format.name)]) ...")

let directory = FilePath.fileDir(outputName)
if !directory.isEmpty {
    try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
}

let sameExtension = FilePath.fileExt(inputName).lowercased() == FilePath.fileExt(outputName).lowercased()
var saveWatch = Stopwatch()
if result.changed || !sameExtension {
    let writeOptions = ImageWriteOptions(jpegQuality: options.jpegCompressionQuality,
                                         tiffCompression: result.resolvedTiffCompression,
                                         resolution: loaded.resolution)
    do {
        try ImageWriter.save(outputImage, to: outputName, options: writeOptions)
    } catch {
        print("")
        print(error)
        exit(1)
    }
} else {
    try? FileManager.default.removeItem(atPath: outputName)
    try? FileManager.default.copyItem(atPath: inputName, toPath: outputName)
}

if options.showTimings {
    print(saveWatch.line("Save output file"))
}

print("Done!")
