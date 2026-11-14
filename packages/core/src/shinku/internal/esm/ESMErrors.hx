package shinku.internal.esm;

import haxe.Exception;

/** package.json configuration is invalid or contains an invalid configuration. */
class InvalidPackageConfigurationError extends Exception {}

/** Module specifier is an invalid URL, package name or package subpath specifier. */
class InvalidModuleSpecifierError extends Exception {}

/** Package exports or imports define a target module for the package that is an invalid type or string target. */
class InvalidPackageTargetError extends Exception {}

/** Package exports do not define or permit a target subpath in the package for the given module. */
class PackagePathNotExportedError extends Exception {}

/** The package or module requested does not exist. */
class ModuleNotFoundError extends Exception {}

/** Package imports do not define the specifier. */
class PackageImportNotDefinedError extends Exception {}

/** The resolved path corresponds to a directory, which is not a supported target for module imports. */
class UnsupportedDirectoryImportError extends Exception {}
