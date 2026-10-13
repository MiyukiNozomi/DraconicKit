import ts from "typescript";

export function tsCompile(
  fileNames: string[],
  options: ts.CompilerOptions,
): Record<string, string> {
  const program = ts.createProgram(fileNames, options);
  const outputs: Record<string, string> = {};

  const originalHost = ts.createCompilerHost(options);

  const host: ts.CompilerHost = {
    ...originalHost,

    writeFile(
      fileName: string,
      data: string,
      writeByteOrderMark: boolean,
      onError?: (message: string) => void,
      sourceFiles?: readonly ts.SourceFile[],
    ) {
      outputs[fileName] = data;
    },
  };

  const emitResult = program.emit(undefined, host.writeFile);

  const allDiagnostics = ts
    .getPreEmitDiagnostics(program)
    .concat(emitResult.diagnostics);

  allDiagnostics.forEach((diagnostic) => {
    if (diagnostic.file && diagnostic.start !== undefined) {
      const { line, character } = ts.getLineAndCharacterOfPosition(
        diagnostic.file,
        diagnostic.start,
      );

      const message = ts.flattenDiagnosticMessageText(
        diagnostic.messageText,
        "\n",
      );

      console.error(
        `${diagnostic.file.fileName} (${line + 1},${character + 1}): ${message}`,
      );
    } else {
      console.error(
        ts.flattenDiagnosticMessageText(diagnostic.messageText, "\n"),
      );
    }
  });

  if (emitResult.emitSkipped) {
    throw "TypeScript build failed!";
  }

  return outputs;
}
