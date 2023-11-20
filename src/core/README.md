# mORMot Core Units

## Folder Content

This folder hosts the Core Units of the *mORMot* Open Source framework, version 2.

## Core Units

With "Core Units", we mean units implementing shared basic functionality of our framework:

- Uncoupled reusable bricks to process files, text, JSON, compression, encryption, network, RTTI, potentially with optimized asm;
- Other higher level features, like ORM, SOA or database access are built on top of those bricks, and are located in the parent folder;
- Cross-Platform and Cross-Compiler: ensure the same code would compile on both FPC and Delphi, on any support platform, regardless the RTL, Operating System, or CPU.

## Units Presentation

### mormot.core.base

Basic types and reusable stand-alone functions shared by all framework units
- Framework Version and Information
- Common Types Used for Compatibility Between Compilers and CPU
- Numbers (floats and integers) Low-level Definitions
- integer Arrays Manipulation
- `ObjArray` `PtrArray` `InterfaceArray` Wrapper Functions
- Low-level Types Mapping Binary or Bits Structures
- Buffers (e.g. Hashing and SynLZ compression) Raw Functions
- Date / Time Processing
- Efficient `Variant` Values Conversion
- Sorting/Comparison Functions
- Some Convenient `TStream` descendants and File access functions
- Faster Alternative to RTL Standard Functions
- Raw Shared Types Definitions

Aim of those types and functions is to be cross-platform and cross-compiler, without any dependency but the main FPC/Delphi RTL. It also detects the kind of Intel/AMD it runs on, to adapt to the fastest asm version available. It is the main unit where x86_64 or i386 asm stubs are included.

### mormot.core.os

Cross-platform functions shared by all framework units
- Some Cross-System Type and Constant Definitions
- Gather Operating System Information
- Operating System Specific Types (e.g. `TWinRegistry`)
- Unicode, Time, File, Console, Library process
- Cross-Platform Charset and CodePage Support
- Per Class Properties O(1) Lookup via `vmtAutoTable` Slot (e.g. for RTTI cache)
- `TSynLocker`/`TSynLocked` and Low-Level Threading Features
- Unix Daemon and Windows Service Support

Aim of this unit is to centralize most used OS-specific API calls, like a `SysUtils` unit on steroids, to avoid `$ifdef/$endif` in "uses" clauses.

In practice, no "Windows", nor "Linux/Unix" reference should be needed in regular units, once `mormot.core.os` is included. :)

### mormot.core.os.mac

MacOS API calls for FPC, as injected to `mormot.core.os.pas`
- Gather MacOS Specific Operating System Information

This unit uses MacOSAll and link several toolkits, so was not included in `mormot.core.os.pas` to reduce executable size, but inject this methods at runtime: just include "`uses mormot.core.os.mac`" in programs needing it.

### mormot.core.unicode

Efficient Unicode Conversion Classes shared by all framework units
- UTF-8 Efficient Encoding / Decoding
- UTF-8 / UTF-16 / Ansi Conversion Classes
- Text File Loading with BOM/Unicode Support
- Low-Level String Conversion Functions
- Text Case-(in)sensitive Conversion and Comparison
- UTF-8 String Manipulation Functions
- `TRawUtf8DynArray` Processing Functions
- Operating-System Independent Unicode Process

### mormot.core.text

Text Processing functions shared by all framework units
- CSV-like Iterations over Text Buffers
- `TTextWriter` parent class for Text Generation
- Numbers (integers or floats) and Variants to Text Conversion
- Text Formatting functions
- Resource and Time Functions
- `ESynException` class
- Hexadecimal Text And Binary Conversion

### mormot.core.datetime

Date and Time definitions and process shared by all framework units
- ISO-8601 Compatible Date/Time Text Encoding
- `TSynDate` / `TSynDateTime` / `TSynSystemTime` High-Level objects
- `TUnixTime` / `TUnixMSTime` POSIX Epoch Compatible 64-bit date/time
- `TTimeLog` efficient 64-bit custom date/time encoding

### mormot.core.rtti

Cross-Compiler RTTI Definitions shared by all framework units
- Low-Level Cross-Compiler RTTI Definitions
- Enumerations RTTI
- Published `class` Properties and Methods RTTI
- `IInvokable` Interface RTTI
- Efficient Dynamic Arrays and Records Process
- Managed Types Finalization or Copy
- RTTI Value Types used for JSON Parsing
- RTTI-based Registration for Custom JSON Parsing
- High Level `TObjectWithID` and `TObjectWithCustomCreate` Class Types
- Redirect Most Used FPC RTL Functions to Optimized x86_64 Assembly

Purpose of this unit is to avoid any direct use of `TypInfo.pas` RTL unit, which is not exactly compatible between compilers, and lacks of direct RTTI access with no memory allocation. We define pointers to RTTI record/object to access `TypeInfo()` via a set of explicit methods. Here fake record/objects are just wrappers around pointers defined in Delphi/FPC RTL's `TypInfo.pas` with the magic of inlining. We redefined all RTTI definitions as `TRtti*` types to avoid confusion with type names as published by the `TypInfo` unit.

At higher level, the new `TRttiCustom` class is the main cached entry of our customizable RTTI,accessible from the global `Rtti.*` methods. It is enhanced in the `mormot.core.json` unit to support JSON.

### mormot.core.buffers

Low-Level Memory Buffers Processing Functions shared by all framework units
- *Variable Length Integer* Encoding / Decoding
- `TAlgoCompress` Compression/Decompression Classes - with `AlgoSynLZ` `AlgoRleLZ`
- `TFastReader` / `TBufferWriter` Binary Streams
- Base64, Base64URI, Base58 and Baudot Encoding / Decoding
- URI-Encoded Text Buffer Process
- Basic MIME Content Types Support
- Text Memory Buffers and Files
- Markup (e.g. HTML or Emoji) process
- `RawByteString` Buffers Aggregation via `TRawByteStringGroup`

### mormot.core.data

Low-Level Data Processing Functions shared by all framework units
- RTL `TPersistent` / `TInterfacedObject` with Custom Constructor
- `TSynPersistent*` / `TSyn*List` classes
- `TSynPersistentStore` with proper Binary Serialization
- INI Files and In-memory Access
- Efficient RTTI Values Binary Serialization and Comparison
- `TDynArray` and `TDynArrayHashed` Wrappers
- `Integer` Arrays Extended Process
- `RawUtf8` String Values Interning and `TRawUtf8List`
- Abstract Radix Tree Classes

### mormot.core.json

JSON functions shared by all framework units
- Low-Level JSON Processing Functions
- `TTextWriter` class with proper JSON escaping and `WriteObject()` support
- JSON-aware `TSynNameValue` `TSynPersistentStoreJson`
- JSON-aware `TSynDictionary` Storage
- JSON Unserialization for any kind of Values
- JSON Serialization Wrapper Functions
- Abstract Classes with Auto-Create-Fields

### mormot.core.collections

 Generics Collections as used by all framework units
 - JSON-aware `IList<>` List Storage
 - JSON-aware `IKeyValue<>` Dictionary Storage
 - Collections Factory for `IList<>` and `IKeyValue<>` Instances

In respect to `generics.collections` from the Delphi or FPC RTL, this unit uses `interface` as variable holders, and leverage them to reduce the generated code as much as possible, as the *Spring4D 2.0 framework* does, but for both Delphi and FPC. As a result, compiled units (`.dcu`/`.ppu`) and executable are much smaller, and faster to compile.

It publishes `TDynArray` and `TSynDictionary` high-level features like indexing, sorting, JSON/binary serialization or thread safety as Generics strong typing.

Use `Collections.NewList<T>` and `Collections.NewKeyValue<TKey, TValue>` factories as main entry points of these efficient data structures.
   
### mormot.core.variants

`Variant` / `TDocVariant` feature shared by all framework units
- Low-Level `Variant` Wrappers
- Custom `Variant` Types with JSON support
- `TDocVariant` Object/Array Document Holder with JSON support
- JSON Parsing into `Variant`

### mormot.core.search

Several Indexing and Search Engines, as used by other parts of the framework
- Files Search in Folders
- ScanUtf8, GLOB and SOUNDEX Text Search
- Efficient CSV Parsing using RTTI
- Versatile Expression Search Engine
- *Bloom Filter* Probabilistic Index
- Binary Buffers Delta Compression
- `TDynArray` Low-Level Binary Search
- `TSynFilter` and `TSynValidate` Processing Classes
- Cross-Platform `TSynTimeZone` Time Zones

### mormot.core.log

Logging functions shared by all framework units
- Debug Symbols Processing from Delphi .map or FPC/GDB DWARF
- Logging via `TSynLogFamily` `TSynLog` `ISynLog`
- High-Level Logs and Exception Related Features
- Efficient `.log` File Access via `TSynLogFile`
- SysLog Messages Support as defined by RFC 5424

### mormot.core.perf

Performance Monitoring functions shared by all framework units
- Performance Counters
- `TSynMonitor` Process Information Classes
- `TSynMonitorUsage` Process Information Database Storage
- Operating System Monitoring
- `DMI`/`SMBIOS` Binary Decoder
- `TSynFPUException` Wrapper for FPU Flags Preservation

### mormot.core.threads

High-Level Multi-Threading features shared by all framework units
- Thread-Safe `TSynQueue` and `TPendingTaskList`
- Thread-Safe `ILockedDocVariant` Storage
- Background Thread Processing
- Parallel Execution in a Thread Pool
- Server Process Oriented Thread Pool

### mormot.core.zip

High-Level Zip/Deflate Compression features shared by all framework units
- `TSynZipCompressor` Stream Class
- GZ Read/Write Support
- `.zip` Archive File Support
- `TAlgoDeflate` and `TAlgoDeflate` High-Level Compression Algorithms

### mormot.core.mustache

Logic-Less `{{Mustache}}` Templates Rendering
- *Mustache* Execution Data Context Types
- `TSynMustache` Template Processing

### mormot.core.interfaces

Implements SOLID Process via Interface types
- `IInvokable` Interface Methods and Parameters RTTI Extraction
- `TInterfaceFactory` Generating Runtime Implementation Class
- `TInterfaceResolver` `TInjectableObject` for IoC / Dependency Injection
- `TInterfaceStub` `TInterfaceMock` for Dependency Mocking
- `TInterfaceMethodExecute` for Method Execution from JSON
- `SetWeak` and `SetWeakZero` Weak Interface Reference Functions

### mormot.core.test

Testing functions shared by all framework units
- Unit-Testing classes and functions

### mormot.core.fpcx64mm

An (optional) Multi-thread Friendly Memory Manager for FPC written in x86_64 assembly
- targetting Linux (and Windows) multi-threaded Services
- only for FPC on the x86_64 target - use the RTL MM on Delphi or ARM
- based on FastMM4 proven algorithms by Pierre le Riche
- code has been reduced to the only necessary featureset for production
- deep asm refactoring for cross-platform, compactness and efficiency
- can report detailed statistics (with threads contention and memory leaks)
- mremap() makes large block ReallocMem a breeze on Linux :)
- inlined SSE2 movaps loop is more efficient that subfunction(s)
- lockless round-robin of tiny blocks (<=128/256 bytes) for better scaling
- optional lockless bin list to avoid freemem() thread contention
- three app modes: default mono-thread friendly, `FPCMM_SERVER` or `FPCMM_BOOST`
<br/>
<br/>
<br/>
<br/>
<br/>
===========================================================<br/>
# ** 中文翻译 ** 


# mORMot 核心单元

## 文件夹内容

此文件夹托管 *mORMot* 开源框架版本 2 的核心单元。

## 核心单元

对于“核心单元”，我们指的是实现我们框架的共享基本功能的单元：

- 解耦的可重用块来处理文件、文本、JSON、压缩、加密、网络、RTTI，可能具有优化的 asm；
- 其他更高级别的功能，如 ORM、SOA 或数据库访问都构建在这些块之上，并且位于父文件夹中；
- 跨平台和交叉编译器：确保相同的代码可以在任何支持平台上的 FPC 和 Delphi 上编译，无论 RTL、操作系统或 CPU。

## 单位介绍

### mormot.core.base

所有框架单元共享的基本类型和可重用的独立函数
- 框架版本及信息
- 用于编译器和CPU之间兼容性的常用类型
- 数字（浮点数和整数）低级定义
- 整数数组操作
- `ObjArray` `PtrArray` `InterfaceArray` 包装函数
- 映射二进制或位结构的低级类型
- 缓冲区（例如散列和 SynLZ 压缩）原始函数
- 日期/时间处理
- 高效的“变体”值转换
- 排序/比较功能
- 一些方便的“TStream”后代和文件访问功能
- RTL 标准函数的更快替代方案
- 原始共享类型定义

这些类型和函数的目标是跨平台和跨编译器，除了主要的 FPC/Delphi RTL 之外没有任何依赖。 它还检测其运行的 Intel/AMD 类型，以适应可用的最快的 asm 版本。 它是包含 x86_64 或 i386 asm 存根的主要单元。

### mormot.core.os

所有框架单元共享的跨平台功能
- 一些跨系统类型和常量定义
- 收集操作系统信息
- 操作系统特定类型（例如`TWinRegistry`）
- Unicode、时间、文件、控制台、库进程
- 跨平台字符集和代码页支持
- 每个类属性 O(1) 通过 `vmtAutoTable` 插槽查找（例如 RTTI 缓存）
- `TSynLocker`/`TSynLocked` 和低级线程功能
- Unix 守护进程和 Windows 服务支持

该单元的目的是集中最常用的特定于操作系统的 API 调用，就像类固醇上的“SysUtils”单元一样，以避免“uses”子句中的“$ifdef/$endif”。

实际上，一旦包含“mormot.core.os”，常规单元中就不需要“Windows”或“Linux/Unix”引用。 :)

### mormot.core.os.mac

MacOS API 调用 FPC，注入“mormot.core.os.pas”
- 收集 MacOS 特定操作系统信息

该单元使用 MacOSAll 并链接多个工具包，因此未包含在 `mormot.core.os.pas` 中以减少可执行文件大小，但在运行时注入此方法：只需在中包含“`uses mormot.core.os.mac`” 需要它的程序。

### mormot.core.unicode

所有框架单元共享的高效 Unicode 转换类
- UTF-8高效编码/解码
- UTF-8 / UTF-16 / Ansi 转换类
- 支持 BOM/Unicode 的文本文件加载
- 低级字符串转换函数
- 文本区分大小写的转换和比较
- UTF-8 字符串操作函数
- `TRawUtf8DynArray` 处理函数
- 独立于操作系统的 Unicode 进程

### mormot.core.text

所有框架单元共享的文本处理功能
- 类似 CSV 的文本缓冲区迭代
- 用于文本生成的“TTextWriter”父类
- 数字（整数或浮点数）和变体到文本的转换
- 文本格式化功能
- 资源和时间函数
- `ESynException` 类
- 十六进制文本和二进制转换

### mormot.core.datetime

所有框架单元共享的日期和时间定义和流程
- ISO-8601 兼容日期/时间文本编码
- `TSynDate` / `TSynDateTime` / `TSynSystemTime` 高级对象
- `TUnixTime` / `TUnixMSTime` POSIX Epoch 兼容 64 位日期/时间
- `TTimeLog` 高效 64 位自定义日期/时间编码

### mormot.core.rtti

所有框架单元共享的交叉编译器 RTTI 定义
- 低级交叉编译器 RTTI 定义
- 枚举RTTI
- 发布了“类”属性和方法 RTTI
- `IInvokable` 接口 RTTI
- 高效的动态数组和记录过程
- 托管类型最终确定或复制
- 用于 JSON 解析的 RTTI 值类型
- 基于 RTTI 的自定义 JSON 解析注册
- 高级 `TObjectWithID` 和 `TObjectWithCustomCreate` 类类型
- 将最常用的 FPC RTL 函数重定向到优化的 x86_64 组件

该单元的目的是避免直接使用 `TypInfo.pas` RTL 单元，该单元在编译器之间不完全兼容，并且缺乏无需内存分配的直接 RTTI 访问。 我们定义指向 RTTI 记录/对象的指针，以通过一组显式方法访问“TypeInfo()”。 这里，假记录/对象只是 Delphi/FPC RTL 的“TypInfo.pas”中定义的指针的包装器，具有内联的魔力。 我们将所有 RTTI 定义重新定义为“TRtti*”类型，以避免与“Ty”发布的类型名称混淆
