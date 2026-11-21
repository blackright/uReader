/// Proposed contract budgets. Never infer safety from declared ZIP sizes alone.
abstract final class EpubLimits {
  static const sourceBytes = 100 * 1024 * 1024;
  static const inflatedBytes = 500 * 1024 * 1024;
  static const entryBytes = 50 * 1024 * 1024;
  static const entries = 5000;
  static const expansionRatio = 100;
  static const directoryBytes = 8 * 1024 * 1024;
  static const entryNameBytes = 1024;
  static const sourceChunkBytes = 65536;
  static const indexPageEntries = 128;
  static const xmlDepth = 128;
  static const attributes = 64;
  static const attributeBytes = 16 * 1024;
  static const markupBytes = 64 * 1024;
  static const xmlElements = 1000000;
  static const metadataDocumentBytes = 2 * 1024 * 1024;
  static const metadataTotalBytes = 8 * 1024 * 1024;
  static const cssSheetBytes = 256 * 1024;
  static const cssTotalBytes = 2 * 1024 * 1024;
  static const cssSelectors = 5000;
  static const cssComplexity = 16;
  static const selectorEvaluations = 2000000;
  static const canonicalUnits = 32 * 1024 * 1024;
  static const blocks = 200000;
  static const blockUnits = 8192;
  static const inlinePerBlock = 128;
  static const imagePixels = 16000000;
  static const imageDimension = 8192;
  static const imageTargetDimension = 2048;
  static const windowBlocks = 64;
  static const windowUnits = 65536;
  static const analysisDeadline = Duration(seconds: 120);
  static const cancellationGrace = Duration(seconds: 2);
}
