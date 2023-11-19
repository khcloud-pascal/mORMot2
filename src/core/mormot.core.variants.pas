
/// Framework Core Low-Level Variants / TDocVariant process
// - this unit is a part of the Open Source Synopse mORMot framework 2,
// licensed under a MPL/GPL/LGPL three license - see LICENSE.md
/// 框架核心低级变体/TDocVariant 流程
// - 本单元是开源 Synopse mORMot 框架 2 的一部分，根据 MPL/GPL/LGPL 三个许可证获得许可 - 请参阅 LICENSE.md
unit mormot.core.variants;

{
  *****************************************************************************

  Variant / TDocVariant feature shared by all framework units
  - Low-Level Variant Wrappers
  - Custom Variant Types with JSON support
  - TDocVariant Object/Array Document Holder with JSON support
  - JSON Parsing into Variant
  - Variant Binary Serialization

所有框架单元共享的 Variant / TDocVariant 功能
   - 低级变体包装器
   - 支持 JSON 的自定义变体类型
   - 支持 JSON 的 TDocVariant 对象/数组文档持有者
   - JSON 解析为变体
   - 变体二进制序列化

  *****************************************************************************
}

interface

{$I ..\mormot.defines.inc}

uses
  sysutils,
  classes,
  variants,
  mormot.core.base,
  mormot.core.os,
  mormot.core.unicode,
  mormot.core.text,
  mormot.core.data, // already included in mormot.core.json  (已经包含在 mormot.core.json 中)
  mormot.core.buffers,
  mormot.core.rtti,
  mormot.core.json;

  
{ ************** Low-Level Variant Wrappers }
{ ************** 低级变体包装器 }

type
  /// exception class raised by this unit during raw Variant process
  /// 在原始 Variant 过程中该单元引发的异常类
  ESynVariant = class(ESynException);

const
  {$ifdef HASVARUSTRING}
  varFirstCustom = varUString + 1;
  {$else}
  varFirstCustom = varAny + 1;
  {$endif HASVARUSTRING}

/// fastcheck if a variant hold a value
// - varEmpty, varNull or a '' string would be considered as void
// - varBoolean=false or varDate=0 would be considered as void
// - a TDocVariantData with Count=0 would be considered as void
// - any other value (e.g. floats or integer) would be considered as not void
/// 快速检查变量是否包含值
// - varEmpty、varNull 或 '' 字符串将被视为 void
// - varBoolean=false 或 varDate=0 将被视为 void
// - Count=0 的 TDocVariantData 将被视为 void
// - 任何其他值（例如浮点数或整数）将被视为非 void
function VarIsVoid(const V: Variant): boolean;

/// returns a supplied string as variant, or null if v is void ('')
/// 返回提供的字符串作为变体，如果 v 为 void ('')，则返回 null
function VarStringOrNull(const v: RawUtf8): variant;

type
  /// a set of simple TVarData.VType, as specified to VarIs()
  /// 一组简单的 TVarData.VType，如 VarIs() 所指定
  TVarDataTypes = set of 0..255;

/// allow to check for a specific set of TVarData.VType
/// 允许检查一组特定的 TVarData.VType
function VarIs(const V: Variant; const VTypes: TVarDataTypes): boolean;
  {$ifdef HASINLINE}inline;{$endif}

/// same as Dest := Source, but copying by reference
// - i.e. VType is defined as varVariant or varByRef / varVariantByRef
// - for instance, it will be used for late binding of TDocVariant properties,
// to let following statements work as expected:
// ! V := _Json('{arr:[1,2]}');
// ! V.arr.Add(3);   // will work, since V.arr will be returned by reference
// ! writeln(V);     // will write '{"arr":[1,2,3]}'
/// 与 Dest := Source 相同，但通过引用复制
// - 即 VType 定义为 varVariant 或 varByRef / varVariantByRef
// - 例如，它将用于 TDocVariant 属性的后期绑定，以使以下语句按预期工作：
// ! V := _Json('{arr:[1,2]}');
// ! V.arr.Add(3);   // will work, since V.arr will be returned by reference
// ! writeln(V);     // will write '{"arr":[1,2,3]}'
procedure SetVariantByRef(const Source: Variant; var Dest: Variant);

/// same as Dest := Source, but copying by value
// - will unreference any varByRef content
// - will convert any string value into RawUtf8 (varString) for consistency
/// 与 Dest := Source 相同，但按值复制
// - 将取消引用任何 varByRef 内容
// - 将任何字符串值转换为 RawUtf8 (varString) 以保持一致性
procedure SetVariantByValue(const Source: Variant; var Dest: Variant);

/// same as FillChar(Value^,SizeOf(TVarData),0)
// - so can be used for TVarData or Variant
// - it will set V.VType := varEmpty, so Value will be Unassigned
// - it won't call VarClear(variant(Value)): it should have been cleaned before
/// 与 FillChar(Value^,SizeOf(TVarData),0) 相同
// - 所以可用于 TVarData 或 Variant
// - 它将设置 V.VType := varEmpty，因此 Value 将被取消分配
// - 它不会调用 VarClear(variant(Value))：它之前应该已经被清理过
procedure ZeroFill(Value: PVarData);
  {$ifdef HASINLINE}inline;{$endif}

/// fill all bytes of the value's memory buffer with zeros, i.e. 'toto' -> #0#0#0#0
// - may be used to cleanup stack-allocated content
/// 用零填充值内存缓冲区的所有字节，即 'toto' -> #0#0#0#0
// - 可用于清理堆栈分配的内容
procedure FillZero(var value: variant); overload;

/// convert an UTF-8 encoded text buffer into a variant RawUtf8 varString
// - this overloaded version expects a destination variant type (e.g. varString
// varOleStr / varUString) - if the type is not handled, will raise an
// EVariantTypeCastError
/// 将 UTF-8 编码的文本缓冲区转换为变体 RawUtf8 varString
// - 此重载版本需要目标变体类型（例如 varString varOleStr / varUString）
// - 如果未处理该类型，将引发 EVariantTypeCastError
procedure RawUtf8ToVariant(const Txt: RawUtf8; var Value: TVarData;
  ExpectedValueType: cardinal); overload;

/// convert an open array (const Args: array of const) argument to a variant
// - note that, due to a Delphi compiler limitation, cardinal values should be
// type-casted to Int64() (otherwise the integer mapped value will be converted)
// - vt*String or vtVariant arguments are returned as varByRef
/// 将开放数组（const Args：const 数组）参数转换为变体
// - 请注意，由于 Delphi 编译器的限制，基数值应类型转换为 Int64() （否则整数映射值将被转换）
// - vt*String 或 vtVariant 参数作为 varByRef 返回
procedure VarRecToVariant(const V: TVarRec; var result: variant); overload;

/// convert an open array (const Args: array of const) argument to a variant
// - note that, due to a Delphi compiler limitation, cardinal values should be
// type-casted to Int64() (otherwise the integer mapped value will be converted)
// - vt*String or vtVariant arguments are returned as varByRef
/// 将开放数组（const Args：const 数组）参数转换为变体
// - 请注意，由于 Delphi 编译器的限制，基数值应类型转换为 Int64() （否则整数映射值将被转换）
// - vt*String 或 vtVariant 参数作为 varByRef 返回
function VarRecToVariant(const V: TVarRec): variant; overload;
  {$ifdef HASINLINE}inline;{$endif}

/// convert a variant to an open array (const Args: array of const) argument
// - variant is accessed by reference as vtVariant so should remain available
/// 将变量转换为开放数组（const Args：const 数组）参数
// - 通过引用作为 vtVariant 访问变量，因此应该保持可用
procedure VariantToVarRec(const V: variant; var result: TVarRec);
  {$ifdef HASINLINE}inline;{$endif}

/// convert a variant array to open array (const Args: array of const) arguments
// - variants are accessed by reference as vtVariant so should remain available
/// 将变体数组转换为开放数组（const Args：const 数组）参数
// - 变体通过引用作为 vtVariant 访问，因此应该保持可用
procedure VariantsToArrayOfConst(const V: array of variant; VCount: PtrInt;
  out result: TTVarRecDynArray); overload;

/// convert a variant array to open array (const Args: array of const) arguments
// - variants are accessed by reference as vtVariant so should remain available
/// 将变体数组转换为开放数组（const Args：const 数组）参数
// - 变体通过引用作为 vtVariant 访问，因此应该保持可用
function VariantsToArrayOfConst(const V: array of variant): TTVarRecDynArray; overload;

/// convert an array of RawUtf8 to open array (const Args: array of const) arguments
// - RawUtf8 are accessed by reference as vtAnsiString so should remain available
/// 将 RawUtf8 数组转换为开放数组（const Args：const 数组）参数
// - RawUtf8 通过引用作为 vtAnsiString 进行访问，因此应该保持可用
function RawUtf8DynArrayToArrayOfConst(const V: array of RawUtf8): TTVarRecDynArray;

/// convert any Variant into a VCL string type
// - expects any varString value to be stored as a RawUtf8
// - prior to Delphi 2009, use VariantToString(aVariant) instead of
// string(aVariant) to safely retrieve a string=AnsiString value from a variant
// generated by our framework units - otherwise, you may loose encoded characters
// - for Unicode versions of Delphi, there won't be any potential data loss,
// but this version may be slightly faster than a string(aVariant)
/// 将任何 Variant 转换为 VCL 字符串类型
// - 期望任何 varString 值存储为 RawUtf8
// - 在 Delphi 2009 之前，使用 VariantToString(aVariant) 而不是 string(aVariant) 从我们的框架单元生成的变体中安全地检索 string=AnsiString 值 - 否则，您可能会丢失编码字符
// - 对于 Delphi 的 Unicode 版本，不会有任何潜在的数据丢失，但此版本可能比字符串（aVariant）稍快
function VariantToString(const V: Variant): string;

/// convert a dynamic array of variants into its JSON serialization
// - will use a TDocVariantData temporary storage
/// 将动态变体数组转换为其 JSON 序列化
// - 将使用 TDocVariantData 临时存储
function VariantDynArrayToJson(const V: TVariantDynArray): RawUtf8;

/// convert a dynamic array of variants into its text values
/// 将动态变量数组转换为其文本值
function VariantDynArrayToRawUtf8DynArray(const V: TVariantDynArray): TRawUtf8DynArray;

/// convert a JSON array into a dynamic array of variants
// - will use a TDocVariantData temporary storage
/// 将 JSON 数组转换为变体的动态数组
// - 将使用 TDocVariantData 临时存储
function JsonToVariantDynArray(const Json: RawUtf8): TVariantDynArray;

/// convert an open array list into a dynamic array of variants
// - will use a TDocVariantData temporary storage
/// 将开放数组列表转换为变体的动态数组
// - 将使用 TDocVariantData 临时存储
function ValuesToVariantDynArray(const items: array of const): TVariantDynArray;

type
  /// function prototype used internally for variant comparison
  // - as used e.g. by TDocVariantData.SortByValue
  /// 内部用于变量比较的函数原型
   // - 如所使用的，例如 通过 TDocVariantData.SortByValue
  TVariantCompare = function(const V1, V2: variant): PtrInt;
  /// function prototype used internally for extended variant comparison
  // - as used by TDocVariantData.SortByRow
  /// 内部用于扩展变体比较的函数原型
   // - 由 TDocVariantData.SortByRow 使用
  TVariantComparer = function(const V1, V2: variant): PtrInt of object;
  /// function prototype used internally for extended variant comparison
  // - as used by TDocVariantData.SortArrayByFields
  /// 内部用于扩展变体比较的函数原型
   // - 由 TDocVariantData.SortArrayByFields 使用
  TVariantCompareField = function(const FieldName: RawUtf8;
    const V1, V2: variant): PtrInt of object;

/// internal function as called by inlined VariantCompare/VariantCompareI and
// the SortDynArrayVariantComp() function overriden by this unit
/// 由内联 VariantCompare/VariantCompareI 调用的内部函数和
// 该单元重写的 SortDynArrayVariantComp() 函数
function FastVarDataComp(A, B: PVarData; caseInsensitive: boolean): integer;

/// TVariantCompare-compatible case-sensitive comparison function
// - just a wrapper around FastVarDataComp(caseInsensitive=false)
/// TVariantCompare 兼容区分大小写的比较函数
// - 只是 FastVarDataComp(caseInsensitive=false) 的包装
function VariantCompare(const V1, V2: variant): PtrInt;
  {$ifdef HASINLINE}inline;{$endif}

/// TVariantCompare-compatible case-insensitive comparison function
// - just a wrapper around FastVarDataComp(caseInsensitive=true)
/// TVariantCompare 兼容的不区分大小写的比较函数
// - 只是 FastVarDataComp(caseInsensitive=true) 的包装
function VariantCompareI(const V1, V2: variant): PtrInt;
  {$ifdef HASINLINE}inline;{$endif}

/// fast comparison of a Variant and UTF-8 encoded String (or number)
// - slightly faster than plain V=Str, which computes a temporary variant
// - here Str='' equals unassigned, null or false
// - if CaseSensitive is false, will use PropNameEquals() for comparison
/// 快速比较 Variant 和 UTF-8 编码的字符串（或数字）
// - 比普通 V=Str 稍快，后者计算临时变量
// - 这里 Str='' 等于未分配、null 或 false
// - 如果 CaseSensitive 为 false，将使用 PropNameEquals() 进行比较
function VariantEquals(const V: Variant; const Str: RawUtf8;
  CaseSensitive: boolean = true): boolean; overload;


{ ************** Custom Variant Types with JSON support }
{ ************** 支持 JSON 的自定义变体类型 }

type
  /// define how our custom variant types behave, i.e. its methods featureset
  /// 定义我们的自定义变体类型的行为方式，即其方法功能集
  TSynInvokeableVariantTypeOptions = set of (
    sioHasTryJsonToVariant,
    sioHasToJson,
    sioCanIterate);

  /// custom variant handler with easier/faster access of variant properties,
  // and JSON serialization support
  // - default GetProperty/SetProperty methods are called via some protected
  // virtual IntGet/IntSet methods, with less overhead (to be overriden)
  // - these kind of custom variants will be faster than the default
  // TInvokeableVariantType for properties getter/setter, but you should
  // manually register each type by calling SynRegisterCustomVariantType()
  // - also feature custom JSON parsing, via TryJsonToVariant() protected method
  /// 自定义变体处理程序，可以更轻松/更快地访问变体属性，并支持 JSON 序列化
   // - 默认的 GetProperty/SetProperty 方法通过一些受保护的虚拟 IntGet/IntSet 方法调用，开销较小（要重写）
   // - 这些类型的自定义变体将比属性 getter/setter 的默认 TInvokeableVariantType 更快，但您应该通过调用 SynRegisterCustomVariantType() 手动注册每种类型
   // - 还具有自定义 JSON 解析功能，通过 TryJsonToVariant() 受保护方法
  TSynInvokeableVariantType = class(TInvokeableVariantType)
  protected
    fOptions: TSynInvokeableVariantTypeOptions;
    {$ifdef ISDELPHI}
    /// our custom call backs do not want the function names to be uppercased
    /// 我们的自定义回调不希望函数名称大写
    function FixupIdent(const AText: string): string; override;
    {$endif ISDELPHI}
    // intercept for a faster direct IntGet/IntSet calls
    // - note: SetProperty/GetProperty are never called by this class/method
    // - also circumvent FPC 3.2+ inverted parameters order
    // 拦截更快的直接 IntGet/IntSet 调用
     // - 注意：此类/方法永远不会调用 SetProperty/GetProperty
     // - 也规避 FPC 3.2+ 反转参数顺序
    {$ifdef FPC_VARIANTSETVAR}
    procedure DispInvoke(Dest: PVarData; var Source: TVarData;
      CallDesc: PCallDesc; Params: Pointer); override;
    {$else} // see http://mantis.freepascal.org/view.php?id=26773
    {$ifdef ISDELPHIXE7}
    procedure DispInvoke(Dest: PVarData; [ref] const Source: TVarData;
      CallDesc: PCallDesc; Params: Pointer); override;
    {$else}
    procedure DispInvoke(Dest: PVarData; const Source: TVarData;
      CallDesc: PCallDesc; Params: Pointer); override;
    {$endif ISDELPHIXE7}
    {$endif FPC_VARIANTSETVAR}
  public
    /// virtual constructor which should set the custom type Options
    /// 虚拟构造函数应设置自定义类型选项
    constructor Create; virtual;
    /// search of a registered custom variant type from its low-level VarType
    // - will first compare with its own VarType for efficiency
    // - returns true and set the matching CustomType if found, false otherwise
    /// 从其低级 VarType 中搜索已注册的自定义变体类型
     // - 首先会与自己的 VarType 进行比较以提高效率
     // - 如果找到则返回 true 并设置匹配的 CustomType，否则返回 false
    function FindSynVariantType(aVarType: cardinal;
      out CustomType: TSynInvokeableVariantType): boolean; overload;
      {$ifdef HASINLINE} inline; {$endif}
    /// search of a registered custom variant type from its low-level VarType
    // - will first compare with its own VarType for efficiency
    /// 从其低级 VarType 中搜索已注册的自定义变体类型
     // - 首先会与自己的 VarType 进行比较以提高效率
    function FindSynVariantType(aVarType: cardinal): TSynInvokeableVariantType; overload;
      {$ifdef HASINLINE} inline; {$endif}
    /// customization of JSON parsing into variants
    // - is enabled only if the sioHasTryJsonToVariant option is set
    // - will be called by e.g. by VariantLoadJson() or GetVariantFromJsonField()
    // with Options: PDocVariantOptions parameter not nil
    // - this default implementation will always returns FALSE,
    // meaning that the supplied JSON is not to be handled by this custom
    // (abstract) variant type
    // - this method could be overridden to identify any custom JSON content
    // and convert it into a dedicated variant instance, then return TRUE
    // - warning: should NOT modify JSON buffer in-place, unless it returns true
    /// 自定义 JSON 解析为变体
     // - 仅当设置了 sioHasTryJsonToVariant 选项时才启用
     // - 将被例如调用 通过 VariantLoadJson() 或 GetVariantFromJsonField() 并使用选项：PDocVariantOptions 参数不为 nil
     // - 此默认实现将始终返回 FALSE，这意味着提供的 JSON 不会由此自定义（抽象）变体类型处理
     // - 可以重写此方法以识别任何自定义 JSON 内容并将其转换为专用变体实例，然后返回 TRUE
     // - 警告：不应就地修改 JSON 缓冲区，除非它返回 true    
    function TryJsonToVariant(var Json: PUtf8Char; var Value: variant;
      EndOfObject: PUtf8Char): boolean; virtual;
    /// customization of variant into JSON serialization
    /// 自定义变体为JSON序列化
    procedure ToJson(W: TJsonWriter; Value: PVarData); overload; virtual;
    /// save a variant as UTF-8 encoded JSON
    // - implemented as a wrapper around ToJson()
    /// 将变体保存为 UTF-8 编码的 JSON
     // - 作为 ToJson() 的包装器实现
    procedure ToJson(Value: PVarData; var Json: RawUtf8;
      const Prefix: RawUtf8 = ''; const Suffix: RawUtf8 = '';
      Format: TTextWriterJsonFormat = jsonCompact); overload; virtual;
    /// clear the content
    // - this default implementation will set VType := varEmpty
    // - override it if your custom type needs to manage its internal memory
    /// 清除内容
     // - 此默认实现将设置 VType := varEmpty
     // - 如果您的自定义类型需要管理其内部内存，则覆盖它
    procedure Clear(var V: TVarData); override;
    /// copy two variant content
    // - this default implementation will copy the TVarData memory
    // - override it if your custom type needs to manage its internal structure
    /// 复制两个变体内容
     // - 此默认实现将复制 TVarData 内存
     // - 如果您的自定义类型需要管理其内部结构，则覆盖它
    procedure Copy(var Dest: TVarData; const Source: TVarData;
      const Indirect: boolean); override;
    /// copy two variant content by value
    // - this default implementation will call the Copy() method
    // - override it if your custom types may use a by reference copy pattern
    /// 按值复制两个变体内容
     // - 此默认实现将调用 Copy() 方法
     // - 如果您的自定义类型可能使用引用复制模式，则覆盖它
    procedure CopyByValue(var Dest: TVarData;
      const Source: TVarData); virtual;
    /// this method will allow to look for dotted name spaces, e.g. 'parent.child'
    // - should return Unassigned if the FullName does not match any value
    // - will identify TDocVariant storage, or resolve and call the generic
    // TSynInvokeableVariantType.IntGet() method until nested value match
    // - you can set e.g. PathDelim = '/' to search e.g. for 'parent/child'
    /// 此方法将允许查找点名称空间，例如 '父母.孩子'
     // - 如果 FullName 与任何值都不匹配，则应返回 Unassigned
     // - 将识别 TDocVariant 存储，或解析并调用通用 TSynInvokeableVariantType.IntGet() 方法，直到嵌套值匹配
     // - 你可以设置例如 PathDelim = '/' 进行搜索，例如 对于“父母/孩子”
    procedure Lookup(var Dest: TVarData; const Instance: TVarData;
      FullName: PUtf8Char; PathDelim: AnsiChar = '.');
    /// will check if the value is an array, and return the number of items
    // - if the document is an array, will return the items count (0 meaning
    // void array) - used e.g. by TSynMustacheContextVariant
    // - this default implementation will return -1 (meaning this is not an array)
    // - overridden method could implement it, e.g. for TDocVariant of kind
    // dvArray - or dvObject (ignoring names) if GetObjectAsValues is true
    /// 将检查该值是否为数组，并返回项目数
     // - 如果文档是一个数组，将返回项目计数（0 表示无效数组） - 例如使用 通过 TSynMustacheContextVariant
     // - 这个默认实现将返回-1（意味着这不是一个数组）
     // - 重写的方法可以实现它，例如 对于 dvArray 类型的 TDocVariant - 或 dvObject（忽略名称）（如果 GetObjectAsValues 为 true）
    function IterateCount(const V: TVarData; GetObjectAsValues: boolean): integer; virtual;
    /// allow to loop over an array document
    // - Index should be in 0..IterateCount-1 range
    // - this default implementation will do nothing
    /// 允许循环遍历数组文档
     // - 索引应该在 0..IterateCount-1 范围内
     // - 这个默认实现不会执行任何操作
    procedure Iterate(var Dest: TVarData; const V: TVarData;
      Index: integer); virtual;
    /// returns TRUE if the supplied variant is of the exact custom type
    /// 如果提供的变体是精确的自定义类型，则返回 TRUE
    function IsOfType(const V: variant): boolean;
      {$ifdef HASINLINE}inline;{$endif}
    /// returns TRUE if the supplied custom variant is void
    // - e.g. returns true for a TDocVariant or TBsonVariant with Count = 0
    // - caller should have ensured that it is of the exact custom type
    /// 如果提供的自定义变体为空，则返回 TRUE
     // - 例如 对于 Count = 0 的 TDocVariant 或 TBsonVariant 返回 true
     // - 调用者应该确保它是准确的自定义类型
    function IsVoid(const V: TVarData): boolean; virtual;
    /// override this abstract method for actual getter by name implementation
    /// 通过名称实现重写这个抽象方法以实现实际的 getter
    function IntGet(var Dest: TVarData; const Instance: TVarData;
      Name: PAnsiChar; NameLen: PtrInt; NoException: boolean): boolean; virtual;
    /// override this abstract method for actual setter by name implementation
    /// 通过名称实现重写此抽象方法以实现实际设置器
    function IntSet(const Instance, Value: TVarData;
      Name: PAnsiChar; NameLen: PtrInt): boolean; virtual;
    /// identify how this custom type behave
    // - as set by the class constructor, to avoid calling any virtual method
    /// 识别此自定义类型的行为方式
     // - 由类构造函数设置，以避免调用任何虚拟方法
    property Options: TSynInvokeableVariantTypeOptions
      read fOptions;
  end;

  /// class-reference type (metaclass) of custom variant type definition
  // - used by SynRegisterCustomVariantType() function
  /// 自定义变体类型定义的类引用类型（元类）
   // - 由 SynRegisterCustomVariantType() 函数使用
  TSynInvokeableVariantTypeClass = class of TSynInvokeableVariantType;

var
  /// internal list of our TSynInvokeableVariantType instances
  // - SynVariantTypes[0] is always DocVariantVType
  // - SynVariantTypes[1] is e.g. BsonVariantType from mormot.db.nosql.bson
  // - instances are owned by Variants.pas as TInvokeableVariantType instances
  // - is defined here for proper FindSynVariantType inlining
  /// TSynInvokeableVariantType 实例的内部列表
   // - SynVariantTypes[0] 始终是 DocVariantVType
   // - SynVariantTypes[1] 是例如 来自 mormot.db.nosql.bson 的 BsonVariantType
   // - 实例由 Variants.pas 作为 TInvokeableVariantType 实例拥有
   // - 此处定义用于正确的 FindSynVariantType 内联
  SynVariantTypes: array of TSynInvokeableVariantType;

/// register a custom variant type to handle properties
// - the registration process is thread-safe
// - this will implement an internal mechanism used to bypass the default
// _DispInvoke() implementation in Variant.pas, to use a faster version
// - is called in case of TDocVariant, TBsonVariant or TSqlDBRowVariant
/// 注册自定义变体类型来处理属性
// - 注册过程是线程安全的
// - 这将实现一个用于绕过默认值的内部机制
// Variant.pas 中的 _DispInvoke() 实现，以使用更快的版本
// - 在 TDocVariant、TBsonVariant 或 TSqlDBRowVariant 的情况下调用
function SynRegisterCustomVariantType(
  aClass: TSynInvokeableVariantTypeClass): TSynInvokeableVariantType;

/// search of a registered custom variant type from its low-level VarType
// - returns the matching custom variant type, nil if not found
/// 从其低级 VarType 中搜索已注册的自定义变体类型
// - 返回匹配的自定义变体类型，如果未找到则返回 nil
function FindSynVariantType(aVarType: cardinal): TSynInvokeableVariantType;
  {$ifdef HASINLINE}inline;{$endif}

/// try to serialize a custom variant value into JSON
// - as used e.g. by TJsonWriter.AddVariant
/// 尝试将自定义变量值序列化为 JSON
// - 如所使用的，例如 通过 TJsonWriter.AddVariant
function CustomVariantToJson(W: TJsonWriter; Value: PVarData;
  Escape: TTextWriterKind): boolean;


{ ************** TDocVariant Object/Array Document Holder with JSON support }
{ ************** TDocVariant 对象/数组文档持有者，支持 JSON }

type
  /// JSON_[] constant convenient TDocVariant options
  // - mVoid defines a safe (and slow) full-copy behavior with [] (no option)
  // - mDefault defines a safe (and slow) full-copy behavior, returning null
  // for unknown fields, as defined e.g. by _Json() and _JsonFmt() functions
  // or JSON_OPTIONS[false]
  // - mFast will copy-by-reference any TDocVariantData content, as defined
  // e.g. by _JsonFast() and _JsonFastFmt() functions or JSON_OPTIONS[true]
  // - mFastFloat will copy-by-reference and can parse floating points as double
  // - mFastStrict will copy-by-reference and only parse strict (quoted) JSON,
  // as defined by JSON_FAST_STRICT global variable
  // - mFastExtended will copy-by-reference and write extended (unquoted) JSON,
  // as defined by JSON_FAST_EXTENDED global variable
  // - mFastExtendedIntern will copy-by-reference, write extended JSON and
  // intern names and values, as defined by JSON_FAST_EXTENDEDINTERN variable
  // - mNameValue will copy-by-reference and check field names case-sensitively,
  // as defined by JSON_NAMEVALUE[false] global variable
  // - mNameValueExtended will copy-by-reference, check field names
  // case-sensitively and write extended (unquoted) JSON,
  // as defined by JSON_NAMEVALUE[true] global variable
  // - mNameValueIntern will copy-by-reference, check field names
  // case-sensitively and intern names and values,
  // as defined by JSON_NAMEVALUEINTERN[false] global variable
  // - mNameValueInternExtended will copy-by-reference, check field names
  // case-sensitively, write extended JSON and intern names and values,
  // as defined by JSON_NAMEVALUEINTERN[true] global variable
  /// JSON_[] 常量方便的 TDocVariant 选项
   // - mVoid 使用 [] 定义安全（且缓慢）的完整复制行为（无选项）
   // - mDefault 定义了安全（且缓慢）的完整复制行为，对于未知字段返回 null，如定义的，例如 通过 _Json() 和 _JsonFmt() 函数或 JSON_OPTIONS[false]
   // - mFast 将按引用复制任何 TDocVariantData 内容，如定义的 通过 _JsonFast() 和 _JsonFastFmt() 函数或 JSON_OPTIONS[true]
   // - mFastFloat 将按引用复制并可以将浮点解析为双精度
   // - mFastStrict 将按引用复制并仅解析严格（引用）JSON，如 JSON_FAST_STRICT 全局变量所定义
   // - mFastExtended 将按引用复制并写入扩展（不带引号）JSON，如 JSON_FAST_EXTENDED 全局变量所定义
   // - mFastExtendedIntern 将按引用复制，写入扩展 JSON 和实习生名称和值，如 JSON_FAST_EXTENDEDINTERN 变量所定义
   // - mNameValue 将按引用复制并区分大小写检查字段名称，如 JSON_NAMEVALUE[false] 全局变量所定义
   // - mNameValueExtended 将按引用复制，区分大小写检查字段名称并写入扩展（不带引号）JSON，如 JSON_NAMEVALUE[true] 全局变量所定义
   // - mNameValueIntern 将按引用复制，区分大小写检查字段名称以及实习生名称和值，如 JSON_NAMEVALUEINTERN[false] 全局变量所定义
   // - mNameValueInternExtended 将按引用复制，区分大小写检查字段名称，写入扩展 JSON 和实习生名称和值，如 JSON_NAMEVALUEINTERN[true] 全局变量所定义  
  TDocVariantModel = (
    mVoid,
    mDefault,
    mFast,
    mFastFloat,
    mFastStrict,
    mFastExtended,
    mFastExtendedIntern,
    mNameValue,
    mNameValueExtended,
    mNameValueIntern,
    mNameValueInternExtended);

var
  /// some convenient TDocVariant options, e.g. as JSON_[fDefault]
  /// 一些方便的 TDoc Variant 选项，例如 作为 JSON[默认]
  JSON_: array[TDocVariantModel] of TDocVariantOptions = (
    // mVoid
    [],
    // mDefault
    [dvoReturnNullForUnknownProperty],
    // mFast
    [dvoReturnNullForUnknownProperty,
     dvoValueCopiedByReference],
    // mFastFloat
    [dvoReturnNullForUnknownProperty,
     dvoValueCopiedByReference,
     dvoAllowDoubleValue],
    // mFastStrict
    [dvoReturnNullForUnknownProperty,
     dvoValueCopiedByReference,
     dvoJsonParseDoNotTryCustomVariants],
    // mFastExtended
    [dvoReturnNullForUnknownProperty,
     dvoValueCopiedByReference,
     dvoSerializeAsExtendedJson],
    // mFastExtendedIntern
    [dvoReturnNullForUnknownProperty,
     dvoValueCopiedByReference,
     dvoSerializeAsExtendedJson,
     dvoJsonParseDoNotTryCustomVariants,
     dvoInternNames,
     dvoInternValues],
    // mNameValue
    [dvoReturnNullForUnknownProperty,
     dvoValueCopiedByReference,
     dvoNameCaseSensitive],
    // mNameValueExtended
    [dvoReturnNullForUnknownProperty,
     dvoValueCopiedByReference,
     dvoNameCaseSensitive,
     dvoSerializeAsExtendedJson],
    // mNameValueIntern
    [dvoReturnNullForUnknownProperty,
     dvoValueCopiedByReference,
     dvoNameCaseSensitive,
     dvoInternNames,
     dvoInternValues],
    // mNameValueInternExtended
    [dvoReturnNullForUnknownProperty,
     dvoValueCopiedByReference,
     dvoNameCaseSensitive,
     dvoInternNames,
     dvoInternValues,
     dvoSerializeAsExtendedJson]
    );

const
  /// same as JSON_[mFast], but can not be used as PDocVariantOptions
  // - handle only currency for floating point values: use JSON_FAST_FLOAT
  // if you want to support double values, with potential precision loss
  /// 与 JSON_[mFast] 相同，但不能用作 PDocVariantOptions
   // - 仅处理浮点值的货币：如果您想支持双精度值，请使用 JSON_FAST_FLOAT，但可能会导致精度损失
  JSON_FAST =
    [dvoReturnNullForUnknownProperty,
     dvoValueCopiedByReference];

  /// same as JSON_FAST, but including dvoAllowDoubleValue for floating
  // point values parsing into double, with potential precision loss
  /// 与 JSON_FAST 相同，但包括 dvoAllowDoubleValue 用于将浮点值解析为双精度，可能会导致精度损失
  JSON_FAST_FLOAT =
    [dvoReturnNullForUnknownProperty,
     dvoValueCopiedByReference,
     dvoAllowDoubleValue];

var
  /// TDocVariant options which may be used for plain JSON parsing
  // - this won't recognize any extended syntax
  /// TDocVariant 选项可用于纯 JSON 解析
   // - 这不会识别任何扩展语法  
  JSON_FAST_STRICT: TDocVariantOptions;

  /// TDocVariant options to be used so that JSON serialization would
  // use the unquoted JSON syntax for field names
  // - you could use it e.g. on a TOrm variant published field to
  // reduce the JSON escape process during storage in the database, by
  // customizing your TOrmModel instance:
  // !  (aModel.Props[TOrmMyRecord]['VariantProp'] as TOrmPropInfoRttiVariant).
  // !    DocVariantOptions := JSON_FAST_EXTENDED;
  // or - in a cleaner way - by overriding TOrm.InternalDefineModel():
  // ! class procedure TOrmMyRecord.InternalDefineModel(Props: TOrmProperties);
  // ! begin
  // !   (Props.Fields.ByName('VariantProp') as TOrmPropInfoRttiVariant).
  // !     DocVariantOptions := JSON_FAST_EXTENDED;
  // ! end;
  // or to set all variant fields at once:
  // ! class procedure TOrmMyRecord.InternalDefineModel(Props: TOrmProperties);
  // ! begin
  // !   Props.SetVariantFieldsDocVariantOptions(JSON_FAST_EXTENDED);
  // ! end;
  // - consider using JSON_NAMEVALUE[true] for case-sensitive
  // TSynNameValue-like storage, or JSON_FAST_EXTENDEDINTERN if you
  // expect RawUtf8 names and values interning
  /// 要使用的 TDocVariant 选项，以便 JSON 序列化将使用不带引号的 JSON 语法作为字段名称
   // - 你可以使用它，例如 通过自定义 TOrmModel 实例，在 TOrm 变体发布字段上减少数据库存储期间的 JSON 转义过程：
   //！ （aModel.Props[TOrmMyRecord]['VariantProp'] 作为 TOrmPropInfoRttiVariant）。
   //！ DocVariantOptions := JSON_FAST_EXTENDED;
   // 或者 - 以更简洁的方式 - 通过重写 TOrm.InternalDefineModel():
   // ! class procedure TOrmMyRecord.InternalDefineModel(Props: TOrmProperties);
   // ! begin
   // !   (Props.Fields.ByName('VariantProp') as TOrmPropInfoRttiVariant).
   // !     DocVariantOptions := JSON_FAST_EXTENDED;
   // ! end;
   // 或者一次设置所有变体字段：
   // ! class procedure TOrmMyRecord.InternalDefineModel(Props: TOrmProperties);
   // ! begin
   // !   Props.SetVariantFieldsDocVariantOptions(JSON_FAST_EXTENDED);
   // ! end;
   // - 考虑使用 JSON_NAMEVALUE[true] 区分大小写
   // 类似 TSynNameValue 的存储，如果您希望使用 RawUtf8 名称和值，则使用 JSON_FAST_EXTENDEDINTERN  
  JSON_FAST_EXTENDED: TDocVariantOptions;

  /// TDocVariant options for JSON serialization with efficient storage
  // - i.e. unquoted JSON syntax for field names and RawUtf8 interning
  // - may be used e.g. for efficient persistence of similar data
  // - consider using JSON_FAST_EXTENDED if you don't expect
  // RawUtf8 names and values interning, or need BSON variants parsing
  /// 用于具有高效存储的 JSON 序列化的 TDocVariant 选项
   // - 即字段名称和 RawUtf8 实习的不带引号的 JSON 语法
   // - 可以使用，例如 相似数据的有效持久化
   // - 如果您不希望 RawUtf8 名称和值实习，或者需要 BSON 变体解析，请考虑使用 JSON_FAST_EXTENDED  
  JSON_FAST_EXTENDEDINTERN: TDocVariantOptions;

  /// TDocVariant options to be used for case-sensitive TSynNameValue-like
  // storage, with optional extended JSON syntax serialization
  // - consider using JSON_FAST_EXTENDED for case-insensitive objects
  /// TDocVariant 选项用于区分大小写的 TSynNameValue 类存储，具有可选的扩展 JSON 语法序列化
   // - 考虑对不区分大小写的对象使用 JSON_FAST_EXTENDED  
  JSON_NAMEVALUE: TDocVariantOptionsBool;

  /// TDocVariant options to be used for case-sensitive TSynNameValue-like
  // storage, RawUtf8 interning and optional extended JSON syntax serialization
  // - consider using JSON_FAST_EXTENDED for case-insensitive objects,
  // or JSON_NAMEVALUE[] if you don't expect names and values interning
  /// TDocVariant 选项用于区分大小写的 TSynNameValue 类存储、RawUtf8 驻留和可选的扩展 JSON 语法序列化
   // - 考虑对不区分大小写的对象使用 JSON_FAST_EXTENDED，如果您不希望名称和值驻留，请考虑使用 JSON_NAMEVALUE[]
  JSON_NAMEVALUEINTERN: TDocVariantOptionsBool;

  // - JSON_OPTIONS[false] is e.g. _Json() and _JsonFmt() functions default
  // - JSON_OPTIONS[true] are used e.g. by _JsonFast() and _JsonFastFmt() functions
  // - handle only currency for floating point values: use JSON_FAST_FLOAT/JSON_[mFastFloat]
  // if you want to support double values, with potential precision loss
  // - JSON_OPTIONS[false] 是例如 _Json() 和 _JsonFmt() 函数默认
   // - JSON_OPTIONS[true] 用于例如 通过 _JsonFast() 和 _JsonFastFmt() 函数
   // - 仅处理浮点值的货币：如果您想支持双精度值，请使用 JSON_FAST_FLOAT/JSON_[mFastFloat]，但可能会导致精度损失  
  JSON_OPTIONS: TDocVariantOptionsBool;

// some slightly more verbose backward compatible options
// 一些稍微详细的向后兼容选项
{$ifndef PUREMORMOT2}
  JSON_OPTIONS_FAST_STRICT: TDocVariantOptions
    absolute JSON_FAST_STRICT;
  JSON_OPTIONS_NAMEVALUE: TDocVariantOptionsBool
    absolute JSON_NAMEVALUE;
  JSON_OPTIONS_NAMEVALUEINTERN: TDocVariantOptionsBool
    absolute JSON_NAMEVALUEINTERN;
  JSON_OPTIONS_FAST_EXTENDED: TDocVariantOptions
    absolute JSON_FAST_EXTENDED;
  JSON_OPTIONS_FAST_EXTENDEDINTERN: TDocVariantOptions
    absolute JSON_FAST_EXTENDEDINTERN;

const
  JSON_OPTIONS_FAST = JSON_FAST;
  JSON_OPTIONS_FAST_FLOAT = JSON_FAST_FLOAT;
{$endif PUREMORMOT2}


type
  /// pointer to a TDocVariant storage
  // - since variants may be stored by reference (i.e. as varByRef), it may
  // be a good idea to use such a pointer via DocVariantData(aVariant)^ or
  // _Safe(aVariant)^ instead of TDocVariantData(aVariant),
  // if you are not sure how aVariant was allocated (may be not _Obj/_Json)
  // - note: due to a local variable lifetime change in Delphi 11, don't use
  // this function with a temporary variant (e.g. from TList<variant>.GetItem) -
  // call _DV() and a local TDocVariantData instead of a PDocVariantData
  /// 指向 TDocVariant 存储的指针
   // - 由于变体可以通过引用存储（即作为 varByRef），因此通过 DocVariantData(aVariant)^ 或 _Safe(aVariant)^ 而不是 TDocVariantData(aVariant) 使用这样的指针可能是个好主意，
   // 如果您不这样做的话 确定 aVariant 是如何分配的（可能不是 _Obj/_Json）
   // - 注意：由于 Delphi 11 中的局部变量生命周期发生变化，请勿将此函数与临时变体一起使用（例如来自 TList<variant>.GetItem）
   // - 调用 _DV() 和本地 TDocVariantData 而不是 PDocVariantData
  PDocVariantData = ^TDocVariantData;

  /// pointer to a dynamic array of TDocVariant storage
  /// 指向 TDocVariant 存储的动态数组的指针
  PDocVariantDataDynArray = array of PDocVariantData;

  /// define the TDocVariant storage layout
  // - if it has one or more named properties, it is a dvObject
  // - if it has no name property, it is a dvArray
  /// 定义 TDocVariant 存储布局
   // - 如果它具有一个或多个命名属性，则它是一个 dvObject
   // - 如果它没有 name 属性，则它是一个 dvArray
  TDocVariantKind = (
    dvUndefined,
    dvObject,
    dvArray);

  /// exception class associated to TDocVariant JSON/BSON document
  /// 与 TDocVariant JSON/BSON 文档关联的异常类
  EDocVariant = class(ESynException)
  protected
    class procedure RaiseSafe(Kind: TDocVariantKind);
  end;

  /// a custom variant type used to store any JSON/BSON document-based content
  // - i.e. name/value pairs for objects, or an array of values (including
  // nested documents), stored in a TDocVariantData memory structure
  // - you can use _Obj()/_ObjFast() _Arr()/_ArrFast() _Json()/_JsonFast() or
  // _JsonFmt()/_JsonFastFmt() functions to create instances of such variants
  // - property access may be done via late-binding - with some restrictions
  // for older versions of FPC, e.g. allowing to write:
  // ! TDocVariant.NewFast(aVariant);
  // ! aVariant.Name := 'John';
  // ! aVariant.Age := 35;
  // ! writeln(aVariant.Name,' is ',aVariant.Age,' years old');
  // - it also supports a small set of pseudo-properties or pseudo-methods:
  // ! aVariant._Count = DocVariantData(aVariant).Count
  // ! aVariant._Kind = ord(DocVariantData(aVariant).Kind)
  // ! aVariant._JSON = DocVariantData(aVariant).JSON
  // ! aVariant._(i) = DocVariantData(aVariant).Value[i]
  // ! aVariant.Value(i) = DocVariantData(aVariant).Value[i]
  // ! aVariant.Value(aName) = DocVariantData(aVariant).Value[aName]
  // ! aVariant.Name(i) = DocVariantData(aVariant).Name[i]
  // ! aVariant.Add(aItem) = DocVariantData(aVariant).AddItem(aItem)
  // ! aVariant._ := aItem = DocVariantData(aVariant).AddItem(aItem)
  // ! aVariant.Add(aName,aValue) = DocVariantData(aVariant).AddValue(aName,aValue)
  // ! aVariant.Exists(aName) = DocVariantData(aVariant).GetValueIndex(aName)>=0
  // ! aVariant.Delete(i) = DocVariantData(aVariant).Delete(i)
  // ! aVariant.Delete(aName) = DocVariantData(aVariant).Delete(aName)
  // ! aVariant.NameIndex(aName) = DocVariantData(aVariant).GetValueIndex(aName)
  // - it features direct JSON serialization/unserialization, e.g.:
  // ! assert(_Json('["one",2,3]')._JSON='["one",2,3]');
  // - it features direct trans-typing into a string encoded as JSON, e.g.:
  // ! assert(_Json('["one",2,3]')='["one",2,3]');
  /// 用于存储任何基于 JSON/BSON 文档的内容的自定义变体类型
   // - 即对象的名称/值对或值数组（包括嵌套文档），存储在 TDocVariantData 内存结构中
   // - 您可以使用 _Obj()/_ObjFast() _Arr()/_ArrFast() _Json()/_JsonFast() 或
   // _JsonFmt()/_JsonFastFmt() 函数用于创建此类变体的实例
   // - 属性访问可以通过后期绑定完成 - 对旧版本的 FPC 有一些限制，例如 允许写：
   // ! TDocVariant.NewFast(aVariant);
   // ! aVariant.Name := 'John';
   // ! aVariant.Age := 35;
   // ! writeln(aVariant.Name,' is ',aVariant.Age,' years old');
   // - 它还支持一小组伪属性或伪方法：
   // ! aVariant._Count = DocVariantData(aVariant).Count
   // ! aVariant._Kind = ord(DocVariantData(aVariant).Kind)
   // ! aVariant._JSON = DocVariantData(aVariant).JSON
   // ! aVariant._(i) = DocVariantData(aVariant).Value[i]
   // ! aVariant.Value(i) = DocVariantData(aVariant).Value[i]
   // ! aVariant.Value(aName) = DocVariantData(aVariant).Value[aName]
   // ! aVariant.Name(i) = DocVariantData(aVariant).Name[i]
   // ! aVariant.Add(aItem) = DocVariantData(aVariant).AddItem(aItem)
   // ! aVariant._ := aItem = DocVariantData(aVariant).AddItem(aItem)
   // ! aVariant.Add(aName,aValue) = DocVariantData(aVariant).AddValue(aName,aValue)
   // ! aVariant.Exists(aName) = DocVariantData(aVariant).GetValueIndex(aName)>=0
   // ! aVariant.Delete(i) = DocVariantData(aVariant).Delete(i)
   // ! aVariant.Delete(aName) = DocVariantData(aVariant).Delete(aName)
   // ! aVariant.NameIndex(aName) = DocVariantData(aVariant).GetValueIndex(aName)
   // - 它具有直接 JSON 序列化/反序列化的功能，例如：
    // ! assert(_Json('["one",2,3]')._JSON='["one",2,3]');
    // - it features direct trans-typing into a string encoded as JSON, e.g.:
    // ! assert(_Json('["one",2,3]')='["one",2,3]');
  TDocVariant = class(TSynInvokeableVariantType)
  protected
    /// name and values interning are shared among all TDocVariantData instances
    /// 名称和值实习在所有 TDocVariantData 实例之间共享
    fInternNames, fInternValues: TRawUtf8Interning;
    fInternSafe: TLightLock; // just protect TRawUtf8Interning initialization
    function CreateInternNames: TRawUtf8Interning;
    function CreateInternValues: TRawUtf8Interning;
  public
    /// initialize a variant instance to store some document-based content
    // - by default, every internal value will be copied, so access of nested
    // properties can be slow - if you expect the data to be read-only or not
    // propagated into another place, set aOptions=[dvoValueCopiedByReference]
    // will increase the process speed a lot
    /// 初始化一个变体实例来存储一些基于文档的内容
     // - 默认情况下，每个内部值都会被复制，因此嵌套属性的访问可能会很慢 - 如果您希望数据是只读的或不传播到另一个地方，设置 aOptions=[dvoValueCopiedByReference] 将提高处理速度 很多
    class procedure New(out aValue: variant;
      aOptions: TDocVariantOptions = []); overload;
      {$ifdef HASINLINE}inline;{$endif}
    /// initialize a variant instance to store per-reference document-based content
    // - same as New(aValue, JSON_FAST);
    // - to be used e.g. as
    // !var
    // !  v: variant;
    // !begin
    // !  TDocVariant.NewFast(v);
    // !  ...
    /// 初始化一个变体实例来存储基于每个引用的文档内容
     // - 与 New(aValue, JSON_FAST) 相同；
     // - 例如使用 作为
    // !var
    // !  v: variant;
    // !begin
    // !  TDocVariant.NewFast(v);
    // !  ...
    class procedure NewFast(out aValue: variant;
      aKind: TDocVariantKind = dvUndefined); overload;
      {$ifdef HASINLINE}inline;{$endif}
    /// ensure a variant is a TDocVariant instance
    // - if aValue is not a TDocVariant, will create a new JSON_FAST
    /// 确保变体是 TDocVariant 实例
     // - 如果aValue不是TDocVariant，将创建一个新的JSON_FAST
    class procedure IsOfTypeOrNewFast(var aValue: variant);
    /// initialize several variant instances to store document-based content
    // - replace several calls to TDocVariantData.InitFast
    // - to be used e.g. as
    // !var
    // !  v1, v2, v3: TDocVariantData;
    // !begin
    // !  TDocVariant.NewFast([@v1,@v2,@v3]);
    // !  ...
    /// 初始化几个变体实例来存储基于文档的内容
     // - 替换对 TDocVariantData.InitFast 的多次调用
     // - 例如使用 作为
    // !var
    // !  v1, v2, v3: TDocVariantData;
    // !begin
    // !  TDocVariant.NewFast([@v1,@v2,@v3]);
    // !  ...
    class procedure NewFast(const aValues: array of PDocVariantData;
      aKind: TDocVariantKind = dvUndefined); overload;
    /// initialize a variant instance to store some document-based content
    // - you can use this function to create a variant, which can be nested into
    // another document, e.g.:
    // ! aVariant := TDocVariant.New;
    // ! aVariant.id := 10;
    // - by default, every internal value will be copied, so access of nested
    // properties can be slow - if you expect the data to be read-only or not
    // propagated into another place, set Options=[dvoValueCopiedByReference]
    // will increase the process speed a lot
    // - in practice, you should better use _Obj()/_ObjFast() _Arr()/_ArrFast()
    // functions or TDocVariant.NewFast()
    /// 初始化一个变体实例来存储一些基于文档的内容
     // - 您可以使用此函数创建一个变体，该变体可以嵌套到
     // 另一个文档，例如：
    // ! aVariant := TDocVariant.New;
    // ! aVariant.id := 10;
     // - 默认情况下，每个内部值都会被复制，因此嵌套属性的访问可能会很慢 - 如果您希望数据是只读的或不传播到另一个地方，设置 Options=[dvoValueCopiedByReference] 将提高处理速度很多
     // - 在实践中，您应该更好地使用 _Obj()/_ObjFast() _Arr()/_ArrFast() 函数或 TDocVariant.NewFast()    
    class function New(Options: TDocVariantOptions = []): variant; overload;
      {$ifdef HASINLINE}inline;{$endif}
    /// initialize a variant instance to store some document-based object content
    // - object will be initialized with data supplied two by two, as Name,Value
    // pairs, e.g.
    // ! aVariant := TDocVariant.NewObject(['name','John','year',1972]);
    // which is the same as:
    // ! TDocVariant.New(aVariant);
    // ! TDocVariantData(aVariant).AddValue('name','John');
    // ! TDocVariantData(aVariant).AddValue('year',1972);
    // - by default, every internal value will be copied, so access of nested
    // properties can be slow - if you expect the data to be read-only or not
    // propagated into another place, set Options=[dvoValueCopiedByReference]
    // will increase the process speed a lot
    // - in practice, you should better use the function _Obj() which is a
    // wrapper around this class method
    /// 初始化一个变体实例来存储一些基于文档的对象内容
     // - 对象将使用两个两个提供的数据进行初始化，如名称、值
     // 对，例如
     // ! aVariant := TDocVariant.NewObject(['name','John','year',1972]);
     // 与以下内容相同：
    // ! TDocVariant.New(aVariant);
    // ! TDocVariantData(aVariant).AddValue('name','John');
    // ! TDocVariantData(aVariant).AddValue('year',1972);
     // - 默认情况下，每个内部值都会被复制，因此嵌套属性的访问可能会很慢 - 如果您希望数据是只读的或不传播到另一个地方，设置 Options=[dvoValueCopiedByReference] 将提高处理速度 很多
     // - 在实践中，您应该更好地使用函数 _Obj()，它是此类方法的包装器
    class function NewObject(const NameValuePairs: array of const;
      Options: TDocVariantOptions = []): variant;
    /// initialize a variant instance to store some document-based array content
    // - array will be initialized with data supplied as parameters, e.g.
    // ! aVariant := TDocVariant.NewArray(['one',2,3.0]);
    // which is the same as:
    // ! TDocVariant.New(aVariant);
    // ! TDocVariantData(aVariant).AddItem('one');
    // ! TDocVariantData(aVariant).AddItem(2);
    // ! TDocVariantData(aVariant).AddItem(3.0);
    // - by default, every internal value will be copied, so access of nested
    // properties can be slow - if you expect the data to be read-only or not
    // propagated into another place, set aOptions=[dvoValueCopiedByReference]
    // will increase the process speed a lot
    // - in practice, you should better use the function _Arr() which is a
    // wrapper around this class method
    /// 初始化一个变体实例来存储一些基于文档的数组内容
     // - 数组将使用作为参数提供的数据进行初始化，例如
    // ! aVariant := TDocVariant.NewArray(['one',2,3.0]);
     // 与以下内容相同：
    // ! TDocVariant.New(aVariant);
    // ! TDocVariantData(aVariant).AddItem('one');
    // ! TDocVariantData(aVariant).AddItem(2);
    // ! TDocVariantData(aVariant).AddItem(3.0);
     // - 默认情况下，每个内部值都会被复制，因此嵌套属性的访问可能会很慢 - 如果您希望数据是只读的或不传播到另一个地方，设置 aOptions=[dvoValueCopiedByReference] 将提高处理速度 很多
     // - 在实践中，您应该更好地使用函数 _Arr()，它是此类方法的包装器
    class function NewArray(const Items: array of const;
      Options: TDocVariantOptions = []): variant; overload;
    /// initialize a variant instance to store some document-based array content
    // - array will be initialized with data supplied dynamic array of variants
    /// 初始化一个变体实例来存储一些基于文档的数组内容
     // - 数组将使用提供的数据进行初始化 动态变量数组
    class function NewArray(const Items: TVariantDynArray;
      Options: TDocVariantOptions = []): variant; overload;
    /// initialize a variant instance to store some document-based object content
    // from a supplied (extended) JSON content
    // - in addition to the JSON RFC specification strict mode, this method will
    // handle some BSON-like extensions, e.g. unquoted field names
    // - a private copy of the incoming JSON buffer will be used, then
    // it will call the TDocVariantData.InitJsonInPlace() method
    // - to be used e.g. as:
    // ! var V: variant;
    // ! begin
    // !   V := TDocVariant.NewJson('{"id":10,"doc":{"name":"John","birthyear":1972}}');
    // !   assert(V.id=10);
    // !   assert(V.doc.name='John');
    // !   assert(V.doc.birthYear=1972);
    // !   // and also some pseudo-properties:
    // !   assert(V._count=2);
    // !   assert(V.doc._kind=ord(dvObject));
    // - or with a JSON array:
    // !   V := TDocVariant.NewJson('["one",2,3]');
    // !   assert(V._kind=ord(dvArray));
    // !   for i := 0 to V._count-1 do
    // !     writeln(V._(i));
    // - by default, every internal value will be copied, so access of nested
    // properties can be slow - if you expect the data to be read-only or not
    // propagated into another place, add dvoValueCopiedByReference in Options
    // will increase the process speed a lot
    // - in practice, you should better use the function _Json()/_JsonFast()
    // which are handy wrappers around this class method
    /// 初始化变体实例以存储来自提供的（扩展）JSON 内容的一些基于文档的对象内容
     // - 除了 JSON RFC 规范严格模式之外，此方法还将处理一些类似 BSON 的扩展，例如 不带引号的字段名称
     // - 将使用传入 JSON 缓冲区的私有副本，然后它将调用 TDocVariantData.InitJsonInPlace() 方法
     // - 例如使用 作为：
    // ! var V: variant;
    // ! begin
    // !   V := TDocVariant.NewJson('{"id":10,"doc":{"name":"John","birthyear":1972}}');
    // !   assert(V.id=10);
    // !   assert(V.doc.name='John');
    // !   assert(V.doc.birthYear=1972);
    // !   // and also some pseudo-properties:
    // !   assert(V._count=2);
    // !   assert(V.doc._kind=ord(dvObject));
     // - 或使用 JSON 数组：
    // !   V := TDocVariant.NewJson('["one",2,3]');
    // !   assert(V._kind=ord(dvArray));
    // !   for i := 0 to V._count-1 do
    // !     writeln(V._(i));
     // - 默认情况下，每个内部值都会被复制，因此嵌套属性的访问可能会很慢 - 如果您希望数据是只读的或不传播到另一个地方，在选项中添加 dvoValueCopiedByReference 将大大提高处理速度
     // - 在实践中，您应该更好地使用函数 _Json()/_JsonFast()，它们是此类方法的方便包装器
    class function NewJson(const Json: RawUtf8;
      Options: TDocVariantOptions = [dvoReturnNullForUnknownProperty]): variant;
      {$ifdef HASINLINE}inline;{$endif}
    /// initialize a variant instance to store some document-based object content
    // from a supplied existing TDocVariant instance
    // - use it on a value returned as varByRef (e.g. by _() pseudo-method),
    // to ensure the returned variant will behave as a stand-alone value
    // - for instance, the following:
    // !  oSeasons := TDocVariant.NewUnique(o.Seasons);
    // is the same as:
    // ! 	oSeasons := o.Seasons;
    // !  _Unique(oSeasons);
    // or even:
    // !  oSeasons := _Copy(o.Seasons);
    /// 初始化变体实例以存储来自提供的现有 TDocVariant 实例的一些基于文档的对象内容
     // - 在作为 varByRef 返回的值上使用它（例如通过 _() 伪方法），以确保返回的变体将表现为独立值
     // - 例如，以下内容：
     // !  oSeasons := TDocVariant.NewUnique(o.Seasons);
     // 是相同的：
     // ! 	oSeasons := o.Seasons;
     // !  _Unique(oSeasons);
     // 甚至：
     // !  oSeasons := _Copy(o.Seasons);
    class function NewUnique(const SourceDocVariant: variant;
      Options: TDocVariantOptions = [dvoReturnNullForUnknownProperty]): variant;
      {$ifdef HASINLINE}inline;{$endif}
    /// will return the unique element of a TDocVariant array or a default
    // - if the value is a dvArray with one single item, it will this value
    // - if the value is not a TDocVariant nor a dvArray with one single item,
    // it wil return the default value
    /// 将返回 TDocVariant 数组的唯一元素或默认值
     // - 如果该值是具有单个项目的 dvArray，则它将是该值
     // - 如果该值不是 TDocVariant 也不是只有一个项目的 dvArray，它将返回默认值
    class procedure GetSingleOrDefault(const docVariantArray, default: variant;
      var result: variant);

    /// finalize the stored information
    /// 最终确定存储的信息
    destructor Destroy; override;
    /// used by dvoInternNames for string interning of all Names[] values
    /// 由 dvoInternNames 用于所有 Names[] 值的字符串驻留
    function InternNames: TRawUtf8Interning;
      {$ifdef HASINLINE}inline;{$endif}
    /// used by dvoInternValues for string interning of all RawUtf8 Values[]
    /// 由 dvoInternValues 用于所有 RawUtf8 Values[] 的字符串驻留
    function InternValues: TRawUtf8Interning;
      {$ifdef HASINLINE}inline;{$endif}
    // this implementation will write the content as JSON object or array
    // 此实现会将内容写入 JSON 对象或数组
    procedure ToJson(W: TJsonWriter; Value: PVarData); override;
    /// will check if the value is an array, and return the number of items
    // - if the document is an array, will return the items count (0 meaning
    // void array) - used e.g. by TSynMustacheContextVariant
    // - this overridden method will implement it for dvArray instance kind
    /// 将检查该值是否为数组，并返回项目数
     // - 如果文档是一个数组，将返回项目计数（0 表示无效数组） - 例如使用 通过 TSynMustacheContextVariant
     // - 这个重写的方法将为 dvArray 实例类型实现它
    function IterateCount(const V: TVarData;
      GetObjectAsValues: boolean): integer; override;
    /// allow to loop over an array document
    // - Index should be in 0..IterateCount-1 range
    // - this default implementation will do handle dvArray instance kind
    /// 允许循环遍历数组文档
     // - 索引应该在 0..IterateCount-1 范围内
     // - 这个默认实现将处理 dvArray 实例类型
    procedure Iterate(var Dest: TVarData; const V: TVarData;
      Index: integer); override;
    /// returns true if this document has Count = 0
    /// 如果此文档的 Count = 0，则返回 true
    function IsVoid(const V: TVarData): boolean; override;
    /// low-level callback to access internal pseudo-methods
    // - mainly the _(Index: integer): variant method to retrieve an item
    // if the document is an array
    /// 访问内部伪方法的低级回调
     // - 主要是 _(Index:integer): 如果文档是数组，则用于检索项目的变体方法
    function DoFunction(var Dest: TVarData; const V: TVarData;
      const Name: string; const Arguments: TVarDataArray): boolean; override;
    /// low-level callback to access internal pseudo-methods
    /// 访问内部伪方法的低级回调
    function DoProcedure(const V: TVarData; const Name: string;
      const Arguments: TVarDataArray): boolean; override;
    /// low-level callback to clear the content
    /// 清除内容的低级回调
    procedure Clear(var V: TVarData); override;
    /// low-level callback to copy two variant content
    // - such copy will by default be done by-value, for safety
    // - if you are sure you will use the variants as read-only, you can set
    // the dvoValueCopiedByReference Option to use faster by-reference copy
    /// 复制两个变体内容的低级回调
     // - 为了安全起见，这种复制默认情况下将按值完成
     // - 如果您确定将使用只读变体，则可以设置 dvoValueCopiedByReference 选项以使用更快的按引用复制
    procedure Copy(var Dest: TVarData; const Source: TVarData;
      const Indirect: boolean); override;
    /// copy two variant content by value
    // - overridden method since instance may use a by-reference copy pattern
    /// 按值复制两个变体内容
     // - 重写方法，因为实例可能使用引用复制模式
    procedure CopyByValue(var Dest: TVarData; const Source: TVarData); override;
    /// handle type conversion
    // - only types processed by now are string/OleStr/UnicodeString/date
    /// 处理类型转换
     // - 目前仅处理的类型是 string/OleStr/UnicodeString/date
    procedure Cast(var Dest: TVarData; const Source: TVarData); override;
    /// handle type conversion
    // - only types processed by now are string/OleStr/UnicodeString/date
    /// 处理类型转换
     // - 目前仅处理的类型是 string/OleStr/UnicodeString/date
    procedure CastTo(var Dest: TVarData; const Source: TVarData;
      const AVarType: TVarType); override;
    /// compare two variant values
    // - redirect to case-sensitive FastVarDataComp() comparison
    /// 比较两个变量值
     // - 重定向到区分大小写的 FastVarDataComp() 比较
    procedure Compare(const Left, Right: TVarData;
      var Relationship: TVarCompareResult); override;
    /// overriden method for actual getter by name implementation
    /// 按名称实现实际 getter 的重写方法
    function IntGet(var Dest: TVarData; const Instance: TVarData;
      Name: PAnsiChar; NameLen: PtrInt; NoException: boolean): boolean; override;
    /// overriden method for actual setter by name implementation
    /// 按名称实现实际设置器的重写方法
    function IntSet(const Instance, Value: TVarData;
      Name: PAnsiChar; NameLen: PtrInt): boolean; override;
  end;

  /// method used by TDocVariantData.ReduceAsArray to filter each object
  // - should return TRUE if the item match the expectations
  /// TDocVariantData.ReduceAsArray 使用的方法来过滤每个对象
   // - 如果项目符合预期，则应返回 TRUE
  TOnReducePerItem = function(Item: PDocVariantData): boolean of object;

  /// method used by TDocVariantData.ReduceAsArray to filter each object
  // - should return TRUE if the item match the expectations
  /// TDocVariantData.ReduceAsArray 使用的方法来过滤每个对象
   // - 如果项目符合预期，则应返回 TRUE
  TOnReducePerValue = function(const Value: variant): boolean of object;

  {$ifdef HASITERATORS}
  /// internal state engine used by TDocVariant enumerators records
  /// TDocVariant 枚举器记录使用的内部状态引擎
  TDocVariantEnumeratorState = record
  private
    Curr, After: PVariant;
  public
    procedure Init(Values: PVariantArray; Count: PtrUInt); inline;
    procedure Void; inline;
    function MoveNext: Boolean; inline;
  end;

  /// local iterated name/value pair as returned by TDocVariantData.GetEnumerator
  // and TDocVariantData.Fields
  // - we use pointers for best performance - but warning: Name may be nil for
  // TDocVariantData.GetEnumerator over an array
  /// TDocVariantData.GetEnumerator 和 TDocVariantData.Fields 返回的本地迭代名称/值对
   // - 我们使用指针以获得最佳性能 - 但警告：对于数组上的 TDocVariantData.GetEnumerator，名称可能为 nil
  TDocVariantFields = record
    /// points to current Name[] - nil if the TDocVariantData is an array
    /// 指向当前 Name[] - 如果 TDocVariantData 是数组则为零
    Name: PRawUtf8;
    /// points to the current Value[] - never nil
    /// 指向当前 Value[] - 绝不为零
    Value: PVariant;
  end;

  /// low-level Enumerator as returned by TDocVariantData.GetEnumerator
  // (default "for .. in dv do") and TDocVariantData.Fields
  /// 由 TDocVariantData.GetEnumerator （默认“for .. in dv do”）和 TDocVariantData.Fields 返回的低级枚举器
  TDocVariantFieldsEnumerator = record
  private
    State: TDocVariantEnumeratorState;
    Name: PRawUtf8;
    function GetCurrent: TDocVariantFields; inline;
  public
    function MoveNext: Boolean; inline;
    function GetEnumerator: TDocVariantFieldsEnumerator; inline;
    /// returns the current Name/Value or Value as pointers in TDocVariantFields
    /// 返回当前名称/值或值作为 TDocVariantFields 中的指针
    property Current: TDocVariantFields
      read GetCurrent;
  end;

  /// low-level Enumerator as returned by TDocVariantData.FieldNames
  /// TDocVariantData.FieldNames 返回的低级枚举器
  TDocVariantFieldNamesEnumerator = record
  private
    Curr, After: PRawUtf8;
  public
    function MoveNext: Boolean; inline;
    function GetEnumerator: TDocVariantFieldNamesEnumerator; inline;
    /// returns the current Name/Value or Value as pointers in TDocVariantFields
    /// 返回当前名称/值或值作为 TDocVariantFields 中的指针
    property Current: PRawUtf8
      read Curr;
  end;

  /// low-level Enumerator as returned by TDocVariantData.Items and FieldValues
  /// 由 TDocVariantData.Items 和 FieldValues 返回的低级枚举器
  TDocVariantItemsEnumerator = record
  private
    State: TDocVariantEnumeratorState;
  public
    function MoveNext: Boolean; inline;
    function GetEnumerator: TDocVariantItemsEnumerator; inline;
    /// returns the current Value as pointer
    /// 返回当前值作为指针
    property Current: PVariant
      read State.Curr;
  end;

  /// low-level Enumerator as returned by TDocVariantData.Objects
  /// TDocVariantData.Objects 返回的低级枚举器
  TDocVariantObjectsEnumerator = record
  private
    State: TDocVariantEnumeratorState;
    Value: PDocVariantData;
  public
    function MoveNext: Boolean; {$ifdef HASSAFEINLINE} inline; {$endif}
    function GetEnumerator: TDocVariantObjectsEnumerator; inline;
    /// returns the current Value as pointer to each TDocVariantData object
    /// 返回当前值作为指向每个 TDocVariantData 对象的指针
    property Current: PDocVariantData
      read Value;
  end;
  {$endif HASITERATORS}

  /// how duplicated values could be searched
  /// 如何搜索重复值
  TSearchDuplicate = (
    sdNone,
    sdCaseSensitive,
    sdCaseInsensitive);

  {$A-} { packet object not allowed since Delphi 2009 :( }
  { 自 Delphi 2009 起不允许使用数据包对象:( }
  /// memory structure used for TDocVariant storage of any JSON/BSON
  // document-based content as variant
  // - i.e. name/value pairs for objects, or an array of values (including
  // nested documents)
  // - you can use _Obj()/_ObjFast() _Arr()/_ArrFast() _Json()/_JsonFast() or
  // _JsonFmt()/_JsonFastFmt() functions to create instances of such variants
  // - you can transtype such an allocated variant into TDocVariantData
  // to access directly its internals (like Count or Values[]/Names[]):
  // ! aVariantObject := TDocVariant.NewObject(['name','John','year',1972]);
  // ! aVariantObject := _ObjFast(['name','John','year',1972]);
  // ! with _Safe(aVariantObject)^ do
  // !   for i := 0 to Count-1 do
  // !     writeln(Names[i],'=',Values[i]); // for an object
  // ! aVariantArray := TDocVariant.NewArray(['one',2,3.0]);
  // ! aVariantArray := _JsonFast('["one",2,3.0]');
  // ! with _Safe(aVariantArray)^ do
  // !   for i := 0 to Count-1 do
  // !     writeln(Values[i]); // for an array
  // - use "with _Safe(...)^ do"  and not "with TDocVariantData(...) do" as the
  // former will handle internal variant redirection (varByRef), e.g. from late
  // binding or assigned another TDocVariant
  // - Delphi "object" is buggy on stack -> also defined as record with methods
  /// 用于 TDocVariant 存储任何基于 JSON/BSON 文档的内容作为变体的内存结构
   // - 即对象的名称/值对，或值数组（包括嵌套文档）
   // - 您可以使用 _Obj()/_ObjFast() _Arr()/_ArrFast() _Json()/_JsonFast() 或
   // _JsonFmt()/_JsonFastFmt() 函数用于创建此类变体的实例
   // - 您可以将此类分配的变体转换为 TDocVariantData 以直接访问其内部（如 Count 或 Values[]/Names[]）：
   // ! aVariantObject := TDocVariant.NewObject(['name','John','year',1972]);
   // ! aVariantObject := _ObjFast(['name','John','year',1972]);
   // ! with _Safe(aVariantObject)^ do
   // !   for i := 0 to Count-1 do
   // !     writeln(Names[i],'=',Values[i]); // for an object
   // ! aVariantArray := TDocVariant.NewArray(['one',2,3.0]);
   // ! aVariantArray := _JsonFast('["one",2,3.0]');
   // ! with _Safe(aVariantArray)^ do
   // !   for i := 0 to Count-1 do
   // !     writeln(Values[i]); // for an array
   // - 使用“with _Safe(...)^ do”而不是“with TDocVariantData(...) do”，因为前者将处理内部变量重定向（varByRef），例如 来自后期绑定或分配另一个 TDocVariant
   // - Delphi“对象”在堆栈上存在错误 -> 也定义为带有方法的记录
  {$ifdef USERECORDWITHMETHODS}
  TDocVariantData = record
  {$else}
  TDocVariantData = object
  {$endif USERECORDWITHMETHODS}
  private
    // note: this structure uses all TVarData available space: no filler needed!
    // 注意：此结构使用所有 TVarData 可用空间：无需填充！
    VType: TVarType;              // 16-bit
    VOptions: TDocVariantOptions; // 16-bit
    VName: TRawUtf8DynArray;      // pointer
    VValue: TVariantDynArray;     // pointer
    VCount: integer;              // 32-bit
    // retrieve the value as varByRef
    // 以 varByRef 形式检索值
    function GetValueOrItem(const aNameOrIndex: variant): variant;
    procedure SetValueOrItem(const aNameOrIndex, aValue: variant);
    // kind is stored as dvoIsArray/dvoIsObject within VOptions
    // kind 在 VOptions 中存储为 dvoIsArray/dvoIsObject
    function GetKind: TDocVariantKind;
      {$ifdef HASINLINE}inline;{$endif}
    procedure SetOptions(const opt: TDocVariantOptions); // keep dvoIsObject/Array
      {$ifdef HASINLINE}inline;{$endif}
    // capacity is Length(VValue) and Length(VName)
    // 容量为 Length(VValue) 和 Length(VName)
    procedure SetCapacity(aValue: integer);
    function GetCapacity: integer;
      {$ifdef HASINLINE}inline;{$endif}
    // implement U[] I[] B[] D[] O[] O_[] A[] A_[] _[] properties
    // 实现 U[] I[] B[] D[] O[] O_[] A[] A_[] _[] 属性
    function GetOrAddIndexByName(const aName: RawUtf8): integer;
      {$ifdef HASINLINE}inline;{$endif}
    function GetOrAddPVariantByName(const aName: RawUtf8): PVariant;
    function GetPVariantByName(const aName: RawUtf8): PVariant;
    function GetRawUtf8ByName(const aName: RawUtf8): RawUtf8;
    procedure SetRawUtf8ByName(const aName, aValue: RawUtf8);
    function GetStringByName(const aName: RawUtf8): string;
    procedure SetStringByName(const aName: RawUtf8; const aValue: string);
    function GetInt64ByName(const aName: RawUtf8): Int64;
    procedure SetInt64ByName(const aName: RawUtf8; const aValue: Int64);
    function GetBooleanByName(const aName: RawUtf8): boolean;
    procedure SetBooleanByName(const aName: RawUtf8; aValue: boolean);
    function GetDoubleByName(const aName: RawUtf8): Double;
    procedure SetDoubleByName(const aName: RawUtf8; const aValue: Double);
    function GetDocVariantExistingByName(const aName: RawUtf8;
      aNotMatchingKind: TDocVariantKind): PDocVariantData;
    function GetObjectExistingByName(const aName: RawUtf8): PDocVariantData;
    function GetDocVariantOrAddByName(const aName: RawUtf8;
      aKind: TDocVariantKind): PDocVariantData;
    function GetObjectOrAddByName(const aName: RawUtf8): PDocVariantData;
    function GetArrayExistingByName(const aName: RawUtf8): PDocVariantData;
    function GetArrayOrAddByName(const aName: RawUtf8): PDocVariantData;
    function GetAsDocVariantByIndex(aIndex: integer): PDocVariantData;
    function GetVariantByPath(const aNameOrPath: RawUtf8): Variant;
      {$ifdef HASINLINE}inline;{$endif}
    function GetObjectProp(const aName: RawUtf8; out aFound: PVariant): boolean;
      {$ifdef FPC}inline;{$endif}
    function InternalAdd(aName: PUtf8Char; aNameLen: integer): integer; overload;
    procedure InternalSetValue(aIndex: PtrInt; const aValue: variant);
      {$ifdef HASINLINE}inline;{$endif}
    procedure InternalUniqueValue(aIndex: PtrInt);
    function InternalNextPath(var aCsv: PUtf8Char; aName: PShortString;
      aPathDelim: AnsiChar): PtrInt;
      {$ifdef FPC}inline;{$endif}
    procedure InternalNotFound(var Dest: variant; aName: PUtf8Char); overload;
    procedure InternalNotFound(var Dest: variant; aIndex: integer); overload;
    function InternalNotFound(aName: PUtf8Char): PVariant; overload;
    function InternalNotFound(aIndex: integer): PDocVariantData; overload;
    procedure ClearFast;
  public
    /// initialize a TDocVariantData to store some document-based content
    // - can be used with a stack-allocated TDocVariantData variable:
    // !var
    // !  Doc: TDocVariantData; // stack-allocated variable
    // !begin
    // !  Doc.Init;
    // !  Doc.AddValue('name','John');
    // !  assert(Doc.Value['name']='John');
    // !  assert(variant(Doc).name='John');
    // !end;
    // - if you call Init*() methods in a row, ensure you call Clear in-between
    /// 初始化一个TDocVariantData来存储一些基于文档的内容
     // - 可与堆栈分配的 TDocVariantData 变量一起使用：
    // !var
    // !  Doc: TDocVariantData; // stack-allocated variable
    // !begin
    // !  Doc.Init;
    // !  Doc.AddValue('name','John');
    // !  assert(Doc.Value['name']='John');
    // !  assert(variant(Doc).name='John');
    // !end;
     // - 如果您连续调用 Init*() 方法，请确保在中间调用 Clear
    procedure Init(aOptions: TDocVariantOptions = []); overload;
      {$ifdef HASINLINE}inline;{$endif}
    /// initialize a TDocVariantData to store a content of some known type
    // - if you call Init*() methods in a row, ensure you call Clear in-between
    /// 初始化 TDocVariantData 来存储某种已知类型的内容
     // - 如果您连续调用 Init*() 方法，请确保在中间调用 Clear
    procedure Init(aOptions: TDocVariantOptions;
      aKind: TDocVariantKind); overload;
    /// initialize a TDocVariantData to store some document-based content
    // - use the options corresponding to the supplied TDocVariantModel
    // - if you call Init*() methods in a row, ensure you call Clear in-between
    /// 初始化一个TDocVariantData来存储一些基于文档的内容
     // - 使用与提供的 TDocVariantModel 相对应的选项
     // - 如果您连续调用 Init*() 方法，请确保在中间调用 Clear
    procedure Init(aModel: TDocVariantModel;
      aKind: TDocVariantKind = dvUndefined); overload;
      {$ifdef HASINLINE}inline;{$endif}
    /// initialize a TDocVariantData to store per-reference document-based content
    // - same as Doc.Init(JSON_FAST);
    // - can be used with a stack-allocated TDocVariantData variable:
    // !var
    // !  Doc: TDocVariantData; // stack-allocated variable
    // !begin
    // !  Doc.InitFast;
    // !  Doc.AddValue('name','John');
    // !  assert(Doc.Value['name']='John');
    // !  assert(variant(Doc).name='John');
    // !end;
    // - see also TDocVariant.NewFast() if you want to initialize several
    // TDocVariantData variable instances at once
    // - if you call Init*() methods in a row, ensure you call Clear in-between
    /// 初始化 TDocVariantData 来存储基于每个引用的文档内容
     // - 与 Doc.Init(JSON_FAST) 相同；
     // - 可与堆栈分配的 TDocVariantData 变量一起使用：
    // !var
    // !  Doc: TDocVariantData; // stack-allocated variable
    // !begin
    // !  Doc.InitFast;
    // !  Doc.AddValue('name','John');
    // !  assert(Doc.Value['name']='John');
    // !  assert(variant(Doc).name='John');
    // !end;
     // - 如果您想初始化多个，另请参见 TDocVariant.NewFast()
     // 一次 TDocVariantData 变量实例
     // - 如果您连续调用 Init*() 方法，请确保在中间调用 Clear
    procedure InitFast(aKind: TDocVariantKind = dvUndefined); overload;
      {$ifdef HASINLINE}inline;{$endif}
    /// initialize a TDocVariantData to store per-reference document-based content
    // - this overloaded method allows to specify an estimation of how many
    // properties or items this aKind document would contain
    /// 初始化 TDocVariantData 来存储基于每个引用的文档内容
     // - 此重载方法允许指定此 aKind 文档将包含多少属性或项目的估计
    procedure InitFast(InitialCapacity: integer; aKind: TDocVariantKind); overload;
    /// initialize a TDocVariantData to store document-based object content
    // - object will be initialized with data supplied two by two, as Name,Value
    // pairs, e.g.
    // !var
    // !  Doc: TDocVariantData; // stack-allocated variable
    // !begin
    // !  Doc.InitObject(['name','John','year',1972]);
    // which is the same as:
    // ! var Doc: TDocVariantData;
    // !begin
    // !  Doc.Init;
    // !  Doc.AddValue('name','John');
    // !  Doc.AddValue('year',1972);
    // - this method is called e.g. by _Obj() and _ObjFast() global functions
    // - if you call Init*() methods in a row, ensure you call Clear in-between
    /// 初始化一个TDocVariantData来存储基于文档的对象内容
     // - 对象将使用两个两个提供的数据进行初始化，如名称、值
     // 对，例如
    // !var
    // !  Doc: TDocVariantData; // stack-allocated variable
    // !begin
    // !  Doc.InitObject(['name','John','year',1972]);
    // which is the same as:
    // ! var Doc: TDocVariantData;
    // !begin
    // !  Doc.Init;
    // !  Doc.AddValue('name','John');
    // !  Doc.AddValue('year',1972);
     // - 这个方法被称为例如 通过 _Obj() 和 _ObjFast() 全局函数
     // - 如果您连续调用 Init*() 方法，请确保在中间调用 Clear
    procedure InitObject(const NameValuePairs: array of const;
      aOptions: TDocVariantOptions = []); overload;
    /// initialize a TDocVariantData to store document-based object content
    // - if you call Init*() methods in a row, ensure you call Clear in-between
    /// 初始化一个TDocVariantData来存储基于文档的对象内容
     // - 如果您连续调用 Init*() 方法，请确保在中间调用 Clear
    procedure InitObject(const NameValuePairs: array of const;
      Model: TDocVariantModel); overload;
    /// initialize a variant instance to store some document-based array content
    // - array will be initialized with data supplied as parameters, e.g.
    // !var
    // !  Doc: TDocVariantData; // stack-allocated variable
    // !begin
    // !  Doc.InitArray(['one',2,3.0]);
    // !  assert(Doc.Count=3);
    // !end;
    // which is the same as:
    // ! var Doc: TDocVariantData;
    // !     i: integer;
    // !begin
    // !  Doc.Init;
    // !  Doc.AddItem('one');
    // !  Doc.AddItem(2);
    // !  Doc.AddItem(3.0);
    // !  assert(Doc.Count=3);
    // !  for i := 0 to Doc.Count-1 do
    // !    writeln(Doc.Value[i]);
    // !end;
    // - this method is called e.g. by _Arr() and _ArrFast() global functions
    // - if you call Init*() methods in a row, ensure you call Clear in-between
    /// 初始化一个变体实例来存储一些基于文档的数组内容
     // - 数组将使用作为参数提供的数据进行初始化，例如
    // !var
    // !  Doc: TDocVariantData; // stack-allocated variable
    // !begin
    // !  Doc.InitArray(['one',2,3.0]);
    // !  assert(Doc.Count=3);
    // !end;
     // 与以下内容相同：
    // ! var Doc: TDocVariantData;
    // !     i: integer;
    // !begin
    // !  Doc.Init;
    // !  Doc.AddItem('one');
    // !  Doc.AddItem(2);
    // !  Doc.AddItem(3.0);
    // !  assert(Doc.Count=3);
    // !  for i := 0 to Doc.Count-1 do
    // !    writeln(Doc.Value[i]);
    // !end;
     // - 这个方法被称为例如 通过 _Arr() 和 _ArrFast() 全局函数
     // - 如果您连续调用 Init*() 方法，请确保在中间调用 Clear
    procedure InitArray(const aItems: array of const;
      aOptions: TDocVariantOptions = []); overload;
    /// initialize a variant instance to store some document-based array content
    // - if you call Init*() methods in a row, ensure you call Clear in-between
    /// 初始化一个变体实例来存储一些基于文档的数组内容
     // - 如果您连续调用 Init*() 方法，请确保在中间调用 Clear
    procedure InitArray(const aItems: array of const;
      aModel: TDocVariantModel); overload;
    /// initialize a variant instance to store some document-based array content
    // - array will be initialized with data supplied as variant dynamic array
    // - if Items is [], the variant will be set as null
    // - will be almost immediate, since TVariantDynArray is reference-counted,
    // unless ItemsCopiedByReference is set to FALSE
    // - if you call Init*() methods in a row, ensure you call Clear in-between
    /// 初始化一个变体实例来存储一些基于文档的数组内容
     // - 数组将使用作为变体动态数组提供的数据进行初始化
     // - 如果 Items 为 []，则变体将设置为 null
     // - 几乎是立即的，因为 TVariantDynArray 是引用计数的，除非 ItemsCopiedByReference 设置为 FALSE
     // - 如果您连续调用 Init*() 方法，请确保在中间调用 Clear
    procedure InitArrayFromVariants(const aItems: TVariantDynArray;
      aOptions: TDocVariantOptions = [];
      aItemsCopiedByReference: boolean = true; aCount: integer = -1);
    /// initialize a variant array instance from an object Values[]
    /// 从对象 Values[] 初始化变体数组实例
    procedure InitArrayFromObjectValues(const aObject: variant;
      aOptions: TDocVariantOptions = []; aItemsCopiedByReference: boolean = true);
    /// initialize a variant array instance from an object Names[]
    /// 从对象 Names[] 初始化变体数组实例
    procedure InitArrayFromObjectNames(const aObject: variant;
      aOptions: TDocVariantOptions = []; aItemsCopiedByReference: boolean = true);
    /// initialize a variant instance to store some RawUtf8 array content
    /// 初始化一个变体实例来存储一些RawUtf8数组内容
    procedure InitArrayFrom(const aItems: TRawUtf8DynArray;
      aOptions: TDocVariantOptions; aCount: integer = -1); overload;
    /// initialize a variant instance to store some 32-bit integer array content
    /// 初始化一个变体实例来存储一些32位整数数组内容
    procedure InitArrayFrom(const aItems: TIntegerDynArray;
      aOptions: TDocVariantOptions; aCount: integer = -1); overload;
    /// initialize a variant instance to store some 64-bit integer array content
    /// 初始化一个变体实例来存储一些64位整数数组内容
    procedure InitArrayFrom(const aItems: TInt64DynArray;
      aOptions: TDocVariantOptions; aCount: integer = -1); overload;
    /// initialize a variant instance to store some double array content
    /// 初始化一个变体实例来存储一些双数组内容
    procedure InitArrayFrom(const aItems: TDoubleDynArray;
      aOptions: TDocVariantOptions; aCount: integer = -1); overload;
    /// initialize a variant instance to store some dynamic array content
    /// 初始化一个变体实例来存储一些动态数组内容
    procedure InitArrayFrom(var aItems; ArrayInfo: PRttiInfo;
      aOptions: TDocVariantOptions; ItemsCount: PInteger = nil); overload;
    /// initialize a variant instance to store some TDynArray content
    /// 初始化一个变体实例来存储一些TDynArray内容
    procedure InitArrayFrom(const aItems: TDynArray;
      aOptions: TDocVariantOptions = JSON_FAST_FLOAT); overload;
    /// initialize a variant instance to store a T*ObjArray content
    // - will call internally ObjectToVariant() to make the conversion
    /// 初始化一个变体实例来存储T*ObjArray内容
     // - 将在内部调用 ObjectToVariant() 进行转换
    procedure InitArrayFromObjArray(const ObjArray; aOptions: TDocVariantOptions;
      aWriterOptions: TTextWriterWriteObjectOptions = [woDontStoreDefault];
      aCount: integer = -1);
    /// fill a TDocVariant array from standard or non-expanded JSON ORM/DB result
    // - accept the ORM/DB results dual formats as recognized by TOrmTableJson,
    // i.e. both [{"f1":"1v1","f2":1v2},{"f2":"2v1","f2":2v2}...] and
    // {"fieldCount":2,"values":["f1","f2","1v1",1v2,"2v1",2v2...],"rowCount":20}
    // - about 2x (expanded) or 3x (non-expanded) faster than Doc.InitJsonInPlace()
    // - will also use less memory, because all object field names will be shared
    // - in expanded mode, the fields order won't be checked, as with TOrmTableJson
    // - warning: the incoming JSON buffer will be modified in-place: so you should
    // make a private copy before running this method, as overloaded procedures do
    /// 从标准或非扩展 JSON ORM/DB 结果填充 TDocVariant 数组
     // - 接受 TOrmTableJson 识别的 ORM/DB 结果双重格式，即 [{"f1":"1v1","f2":1v2},{"f2":"2v1","f2":2v2} ...] 和 {"fieldCount":2,"values":["f1","f2","1v1",1v2,"2v1",2v2...],"rowCount":20}
     // - 比 Doc.InitJsonInPlace() 快大约 2 倍（展开）或 3 倍（非展开）
     // - 也将使用更少的内存，因为所有对象字段名称将被共享
     // - 在扩展模式下，不会检查字段顺序，与 TOrmTableJson 一样
     // - 警告：传入的 JSON 缓冲区将被就地修改：因此您应该在运行此方法之前创建一个私有副本，就像重载过程一样
    function InitArrayFromResults(Json: PUtf8Char; JsonLen: PtrInt;
      aOptions: TDocVariantOptions = JSON_FAST_FLOAT): boolean; overload;
    /// fill a TDocVariant array from standard or non-expanded JSON ORM/DB result
    // - accept the ORM/DB results dual formats as recognized by TOrmTableJson
    // - about 2x (expanded) or 3x (non-expanded) faster than Doc.InitJson()
    // - will also use less memory, because all object field names will be shared
    // - in expanded mode, the fields order won't be checked, as with TOrmTableJson
    // - a private copy of the incoming JSON buffer will be used before parsing
    /// 从标准或非扩展 JSON ORM/DB 结果填充 TDocVariant 数组
     // - 接受 TOrmTableJson 识别的 ORM/DB 结果双格式
     // - 比 Doc.InitJson() 快大约 2 倍（展开）或 3 倍（非展开）
     // - 也将使用更少的内存，因为所有对象字段名称将被共享
     // - 在扩展模式下，不会检查字段顺序，与 TOrmTableJson 一样
     // - 在解析之前将使用传入 JSON 缓冲区的私有副本
    function InitArrayFromResults(const Json: RawUtf8;
      aOptions: TDocVariantOptions = JSON_FAST_FLOAT): boolean; overload;
    /// fill a TDocVariant array from standard or non-expanded JSON ORM/DB result
    // - accept the ORM/DB results dual formats as recognized by TOrmTableJson
    // - about 2x (expanded) or 3x (non-expanded) faster than Doc.InitJson()
    // - will also use less memory, because all object field names will be shared
    // - in expanded mode, the fields order won't be checked, as with TOrmTableJson
    // - a private copy of the incoming JSON buffer will be used before parsing
    /// 从标准或非扩展 JSON ORM/DB 结果填充 TDocVariant 数组
     // - 接受 TOrmTableJson 识别的 ORM/DB 结果双格式
     // - 比 Doc.InitJson() 快大约 2 倍（展开）或 3 倍（非展开）
     // - 也将使用更少的内存，因为所有对象字段名称将被共享
     // - 在扩展模式下，不会检查字段顺序，与 TOrmTableJson 一样
     // - 在解析之前将使用传入 JSON 缓冲区的私有副本
    function InitArrayFromResults(const Json: RawUtf8;
      aModel: TDocVariantModel): boolean; overload;
      {$ifdef HASINLINE} inline; {$endif}
    /// initialize a variant instance to store some document-based object content
    // - object will be initialized with names and values supplied as dynamic arrays
    // - if aNames and aValues are [] or do have matching sizes, the variant
    // will be set as null
    // - will be almost immediate, since Names and Values are reference-counted
    // - if you call Init*() methods in a row, ensure you call Clear in-between
    /// 初始化一个变体实例来存储一些基于文档的对象内容
     // - 对象将使用动态数组提供的名称和值进行初始化
     // - 如果 aNames 和 aValues 为 [] 或确实具有匹配的大小，则变体将设置为 null
     // - 几乎是立即的，因为名称和值是引用计数的
     // - 如果您连续调用 Init*() 方法，请确保在中间调用 Clear
    procedure InitObjectFromVariants(const aNames: TRawUtf8DynArray;
       const aValues: TVariantDynArray; aOptions: TDocVariantOptions = []);
    /// initialize a variant instance to store a document-based object with a
    // single property
    // - the supplied path could be 'Main.Second.Third', to create nested
    // objects, e.g. {"Main":{"Second":{"Third":value}}}
    // - if you call Init*() methods in a row, ensure you call Clear in-between
    /// 初始化一个变体实例来存储具有单个属性的基于文档的对象
     // - 提供的路径可以是“Main.Second.Third”，用于创建嵌套对象，例如 {“主”：{“第二”：{“第三”：值}}}
     // - 如果您连续调用 Init*() 方法，请确保在中间调用 Clear
    procedure InitObjectFromPath(const aPath: RawUtf8; const aValue: variant;
      aOptions: TDocVariantOptions = []; aPathDelim: AnsiChar = '.');
    /// initialize a variant instance to store some document-based object content
    // from a supplied JSON array or JSON object content
    // - warning: the incoming JSON buffer will be modified in-place: so you should
    // make a private copy before running this method, as InitJson() does
    // - this method is called e.g. by _JsonFmt() _JsonFastFmt() global functions
    // with a temporary JSON buffer content created from a set of parameters
    // - if you call Init*() methods in a row, ensure you call Clear in-between
    // - consider the faster InitArrayFromResults() from ORM/SQL JSON results
    /// 初始化变体实例以存储来自提供的 JSON 数组或 JSON 对象内容的一些基于文档的对象内容
     // - 警告：传入的 JSON 缓冲区将被就地修改：所以你应该
     // 在运行此方法之前创建一个私有副本，就像 InitJson() 所做的那样
     // - 这个方法被称为例如 通过 _JsonFmt() _JsonFastFmt() 全局函数，具有从一组参数创建的临时 JSON 缓冲区内容
     // - 如果您连续调用 Init*() 方法，请确保在中间调用 Clear
     // - 考虑来自 ORM/SQL JSON 结果的更快的 InitArrayFromResults()
    function InitJsonInPlace(Json: PUtf8Char;
      aOptions: TDocVariantOptions = [];
      aEndOfObject: PUtf8Char = nil): PUtf8Char;
    /// initialize a variant instance to store some document-based object content
    // from a supplied JSON array or JSON object content
    // - a private copy of the incoming JSON buffer will be used, then
    // it will call the other overloaded InitJsonInPlace() method
    // - this method is called e.g. by _Json() and _JsonFast() global functions
    // - if you call Init*() methods in a row, ensure you call Clear in-between
    // - handle only currency for floating point values: set JSON_FAST_FLOAT
    // or dvoAllowDoubleValue option to support double, with potential precision loss
    // - consider the faster InitArrayFromResults() from ORM/SQL JSON results
    /// 初始化变体实例以存储来自提供的 JSON 数组或 JSON 对象内容的一些基于文档的对象内容
     // - 将使用传入 JSON 缓冲区的私有副本，然后它将调用另一个重载的 InitJsonInPlace() 方法
     // - 这个方法被称为例如 通过 _Json() 和 _JsonFast() 全局函数
     // - 如果您连续调用 Init*() 方法，请确保在中间调用 Clear
     // - 仅处理浮点值的货币：设置 JSON_FAST_FLOAT 或 dvoAllowDoubleValue 选项以支持双精度，但可能会导致精度损失
     // - 考虑来自 ORM/SQL JSON 结果的更快的 InitArrayFromResults()
    function InitJson(const Json: RawUtf8;
      aOptions: TDocVariantOptions = []): boolean; overload;
    /// initialize a variant instance to store some document-based object content
    // from a supplied JSON array or JSON object content
    // - use the options corresponding to the supplied TDocVariantModel
    // - a private copy of the incoming JSON buffer will be made
    // - if you call Init*() methods in a row, ensure you call Clear in-between
    // - handle only currency for floating point values unless you set mFastFloat
    // - consider the faster InitArrayFromResults() from ORM/SQL JSON results
    /// 初始化变体实例以存储来自提供的 JSON 数组或 JSON 对象内容的一些基于文档的对象内容
     // - 使用与提供的 TDocVariantModel 相对应的选项
     // - 将创建传入 JSON 缓冲区的私有副本
     // - 如果您连续调用 Init*() 方法，请确保在中间调用 Clear
     // - 仅处理浮点值的货币，除非您设置 mFastFloat
     // - 考虑来自 ORM/SQL JSON 结果的更快的 InitArrayFromResults()
    function InitJson(const Json: RawUtf8; aModel: TDocVariantModel): boolean; overload;
      {$ifdef HASINLINE}inline;{$endif}
    /// initialize a variant instance to store some document-based object content
    // from a file containing some JSON array or JSON object
    // - file may have been serialized using the SaveToJsonFile() method
    // - if you call Init*() methods in a row, ensure you call Clear in-between
    // - handle only currency for floating point values: set JSON_FAST_FLOAT
    // or dvoAllowDoubleValue option to support double, with potential precision loss
    // - will assume text file with no BOM is already UTF-8 encoded
    /// 初始化一个变体实例以存储包含某些 JSON 数组或 JSON 对象的文件中的一些基于文档的对象内容
     // - 文件可能已使用 SaveToJsonFile() 方法序列化
     // - 如果您连续调用 Init*() 方法，请确保在中间调用 Clear
     // - 仅处理浮点值的货币：设置 JSON_FAST_FLOAT 或 dvoAllowDoubleValue 选项以支持双精度，但可能会导致精度损失
     // - 假设没有 BOM 的文本文件已经是 UTF-8 编码的
    function InitJsonFromFile(const FileName: TFileName;
      aOptions: TDocVariantOptions = []): boolean;
    /// ensure a document-based variant instance will have one unique options set
    // - this will create a copy of the supplied TDocVariant instance, forcing
    // all nested events to have the same set of Options
    // - you can use this function to ensure that all internal properties of this
    // variant will be copied e.g. per-reference (if you set JSON_[mDefault])
    // or per-value (if you set JSON_[mDefault]) whatever options the nested
    // objects or arrays were created with
    // - will raise an EDocVariant if the supplied variant is not a TDocVariant
    // - you may rather use _Unique() or _UniqueFast() wrappers if you want to
    // ensure that a TDocVariant instance is unique
    // - if you call Init*() methods in a row, ensure you call Clear in-between
    /// 确保基于文档的变体实例将具有一个唯一的选项集
     // - 这将创建所提供的 TDocVariant 实例的副本，强制所有嵌套事件具有相同的选项集
     // - 您可以使用此函数来确保复制此变体的所有内部属性，例如 每个引用（如果您设置 JSON_[mDefault]）或每个值（如果您设置 JSON_[mDefault]）无论创建嵌套对象或数组时使用的选项
     // - 如果提供的变体不是 TDocVariant，将引发 EDocVariant
     // - 如果您想确保 TDocVariant 实例是唯一的，您可能更愿意使用 _Unique() 或 _UniqueFast() 包装器
     // - 如果您连续调用 Init*() 方法，请确保在中间调用 Clear
    procedure InitCopy(const SourceDocVariant: variant;
      aOptions: TDocVariantOptions);
    /// clone a document-based variant with the very same options but no data
    // - the same options will be used, without the dvArray/dvObject flags
    // - if you call Init*() methods in a row, ensure you call Clear in-between
    /// 克隆一个基于文档的变体，具有相同的选项，但没有数据
     // - 将使用相同的选项，但没有 dvArray/dvObject 标志
     // - 如果您连续调用 Init*() 方法，请确保在中间调用 Clear
    procedure InitClone(const CloneFrom: TDocVariantData);
      {$ifdef HASINLINE}inline;{$endif}
    /// low-level copy a document-based variant with the very same options and count
    // - if you call Init*() methods in a row, ensure you call Clear in-between
    // - will copy Count and Names[] by reference, but Values[] only if CloneValues
    // - returns the first item in Values[]
    /// 低级复制具有相同选项和计数的基于文档的变体
     // - 如果您连续调用 Init*() 方法，请确保在中间调用 Clear
     // - 将通过引用复制 Count 和 Names[]，但仅当 CloneValues 时才复制 Values[]
     // - 返回 Values[] 中的第一项
    function InitFrom(const CloneFrom: TDocVariantData; CloneValues: boolean;
      MakeUnique: boolean = false): PVariant;
      {$ifdef HASINLINE}inline;{$endif}
    /// initialize a variant instance to store some document-based object content
    // from a supplied CSV UTF-8 encoded text
    // - the supplied content may have been generated by ToTextPairs() method
    // - if ItemSep=#10, then any kind of line feed (CRLF or LF) will be handled
    // - if you call Init*() methods in a row, ensure you call Clear in-between
    /// 初始化变体实例以存储来自提供的 CSV UTF-8 编码文本的一些基于文档的对象内容
     // - 提供的内容可能是由 ToTextPairs() 方法生成的
     // - 如果 ItemSep=#10，则将处理任何类型的换行符（CRLF 或 LF）
     // - 如果您连续调用 Init*() 方法，请确保在中间调用 Clear
    procedure InitCsv(aCsv: PUtf8Char; aOptions: TDocVariantOptions;
      NameValueSep: AnsiChar = '='; ItemSep: AnsiChar = #10;
      DoTrim: boolean = true); overload;
    /// initialize a variant instance to store some document-based object content
    // from a supplied CSV UTF-8 encoded text
    // - the supplied content may have been generated by ToTextPairs() method
    // - if ItemSep = #10, then any kind of line feed (CRLF or LF) will be handled
    // - if you call Init*() methods in a row, ensure you call Clear in-between
    procedure InitCsv(const aCsv: RawUtf8; aOptions: TDocVariantOptions;
      NameValueSep: AnsiChar = '='; ItemSep: AnsiChar = #10;
      DoTrim: boolean = true); overload;
       {$ifdef HASINLINE}inline;{$endif}

    /// to be called before any Init*() method call, when a previous Init*()
    // has already be performed on the same instance, to avoid memory leaks
    // - for instance:
    // !var
    // !  Doc: TDocVariantData; // stack-allocated variable
    // !begin
    // !  Doc.InitArray(['one',2,3.0]); // no need of any Doc.Clear here
    // !  assert(Doc.Count=3);
    // !  Doc.Clear; // to release memory before following InitObject()
    // !  Doc.InitObject(['name','John','year',1972]);
    // !end;
    // - will check the VType, and call ClearFast private method
    /// 当先前的 Init*() 已在同一实例上执行时，在任何 Init*() 方法调用之前调用，以避免内存泄漏
     // - 例如：
     // !var
     // !  Doc: TDocVariantData; // stack-allocated variable
     // !begin
     // !  Doc.InitArray(['one',2,3.0]); // no need of any Doc.Clear here
     // !  assert(Doc.Count=3);
     // !  Doc.Clear; // to release memory before following InitObject()
     // !  Doc.InitObject(['name','John','year',1972]);
     // !end;
     // - 将检查 VType，并调用 ClearFast 私有方法
    procedure Clear;
    /// delete all internal stored values
    // - like Clear + Init() with the same options
    // - will reset Kind to dvUndefined
    /// 删除所有内部存储的值
     // - 像 Clear + Init() 一样具有相同的选项
     // - 将 Kind 重置为 dvUndefine
    procedure Reset;
    /// fill all Values[] with #0, then delete all values
    // - could be used to specifically remove sensitive information from memory
    /// 用#0填充所有Values[]，然后删除所有值
     // - 可用于专门从内存中删除敏感信息
    procedure FillZero;
    /// check if the Document is an object - i.e. Kind = dvObject
    /// 检查 Document 是否是一个对象 - 即 Kind = dvObject
    function IsObject: boolean;
      {$ifdef HASINLINE} inline; {$endif}
    /// check if the Document is an array - i.e. Kind = dvArray
    /// 检查 Document 是否是数组 - 即 Kind = dvArray
    function IsArray: boolean;
      {$ifdef HASINLINE} inline; {$endif}
    /// check if names lookups are case sensitive in this object Document
    /// 检查此对象文档中的名称查找是否区分大小写
    function IsCaseSensitive: boolean;
      {$ifdef HASINLINE} inline; {$endif}
    /// guess the TDocVariantModel corresponding to the current document Options
    // - returns true if model has been found and set
    // - returns false if no JSON_[] matches the current options
    /// 猜测当前文档Options对应的TDocVariantModel
     // - 如果已找到并设置模型，则返回 true
     // - 如果没有 JSON_[] 与当前选项匹配，则返回 false
    function GetModel(out model: TDocVariantModel): boolean;
    /// low-level method to force a number of items
    // - could be used to fast add items to the internal Values[]/Names[] arrays
    // - just set protected VCount field, do not resize the arrays: caller
    // should ensure that Capacity is big enough
    /// 强制多个项目的低级方法
     // - 可用于快速将项目添加到内部 Values[]/Names[] 数组
     // - 只需设置受保护的 VCount 字段，不要调整数组大小：调用者应确保容量足够大
    procedure SetCount(aCount: integer);
      {$ifdef HASINLINE}inline;{$endif}
    /// efficient comparison of two TDocVariantData content
    // - will return the same result than JSON comparison, but more efficiently
    /// 高效比较两个TDocVariantData内容
     // - 将返回与 JSON 比较相同的结果，但效率更高
    function Compare(const Another: TDocVariantData;
      CaseInsensitive: boolean = false): integer; overload;
    /// efficient comparison of two TDocVariantData objects
    // - will always ensure that both this instance and Another are Objects
    // - will compare all values following the supplied Fields order
    // - if no Fields is specified, will fallback to regular Compare()
    /// 两个 TDocVariantData 对象的高效比较
     // - 将始终确保此实例和另一个实例都是对象
     // - 将比较遵循提供的字段顺序的所有值
     // - 如果未指定任何字段，将回退到常规 Compare()
    function CompareObject(const ObjFields: array of RawUtf8;
      const Another: TDocVariantData; CaseInsensitive: boolean = false): integer;
    /// efficient equality comparison of two TDocVariantData content
    // - just a wrapper around Compare(Another)=0
    /// 两个TDocVariantData内容的高效相等比较
     // - 只是 Compare(Another)=0 的包装
    function Equals(const Another: TDocVariantData;
      CaseInsensitive: boolean = false): boolean; overload;
      {$ifdef HASSAFEINLINE}inline;{$endif}
    /// compare a TTDocVariantData object property with a given value
    // - returns -1 if this instance is not a dvObject or has no aName property
    /// 将 TTDocVariantData 对象属性与给定值进行比较
     // - 如果此实例不是 dvObject 或没有 aName 属性，则返回 -1
    function Compare(const aName: RawUtf8; const aValue: variant;
      aCaseInsensitive: boolean = false): integer; overload;
      {$ifdef ISDELPHI}{$ifdef HASINLINE}inline;{$endif}{$endif}
    /// efficient equality comparison a TTDocVariantData object property
    /// 高效相等比较 TTDocVariantData 对象属性
    function Equals(const aName: RawUtf8; const aValue: variant;
      aCaseInsensitive: boolean = false): boolean; overload;
      {$ifdef ISDELPHI}{$ifdef HASINLINE}inline;{$endif}{$endif}
    /// low-level method called internally to reserve place for new values
    // - returns the index of the newly created item in Values[]/Names[] arrays
    // - you should not have to use it, unless you want to add some items
    // directly within the Values[]/Names[] arrays, using e.g.
    // InitFast(InitialCapacity) to initialize the document
    // - if aName='', append a dvArray item, otherwise append a dvObject field
    // - you can specify an optional aIndex value to Insert instead of Add
    // - warning: FPC optimizer is confused by Values[InternalAdd(name)] so
    // you should call InternalAdd() in an explicit previous step
    /// 内部调用低级方法为新值保留位置
     // - 返回 Values[]/Names[] 数组中新创建项目的索引
     // - 您不必使用它，除非您想直接在 Values[]/Names[] 数组中添加一些项目，例如使用 InitFast(InitialCapacity) 初始化文档
     // - 如果 aName=''，则附加一个 dvArray 项，否则附加一个 dvObject 字段
     // - 您可以指定一个可选的 aIndex 值来插入而不是添加
     // - 警告：FPC 优化器被 Values[InternalAdd(name)] 混淆，因此您应该在显式的上一步中调用 InternalAdd()
    function InternalAdd(const aName: RawUtf8; aIndex: integer = -1): integer; overload;
    {$ifdef HASITERATORS}
    /// an enumerator able to compile "for .. in dv do" statements
    // - returns pointers over all Names[] and Values[]
    // - warning: if the document is an array, returned Name is nil:
    // ! var e: TDocVariantFields;
    // ! ...
    // !    dv.InitArray([1, 3, 3, 4]);
    // !    for e in dv do
    // !      // here e.Name = nil
    // !      writeln(e.Value^);
    // ! // output  1  2  3  4
    /// 能够编译“for .. in dv do”语句的枚举器
     // - 返回所有 Names[] 和 Values[] 上的指针
     // - 警告：如果文档是数组，则返回的 Name 为 nil：
    // ! var e: TDocVariantFields;
    // ! ...
    // !    dv.InitArray([1, 3, 3, 4]);
    // !    for e in dv do
    // !      // here e.Name = nil
    // !      writeln(e.Value^);
    // ! // output  1  2  3  4
    function GetEnumerator: TDocVariantFieldsEnumerator;
    /// an enumerator able to compile "for .. in dv.Fields do" for objects
    // - returns pointers over all Names[] and Values[]
    // - don't iterate if the document is an array - so Name is never nil:
    // ! var e: TDocVariantFields;
    // ! ...
    // !   dv.InitJson('{a:1,b:2,c:3}');
    // !   for e in dv.Fields do
    // !     writeln(e.Name^, ':', e.Value^);
    // ! // output  a:1  b:2  c:3
    /// 能够为对象编译“for .. in dv.Fields do”的枚举器
     // - 返回所有 Names[] 和 Values[] 上的指针
     // - 如果文档是数组，则不要迭代 - 所以 Name 永远不会为零：
    // ! var e: TDocVariantFields;
    // ! ...
    // !   dv.InitJson('{a:1,b:2,c:3}');
    // !   for e in dv.Fields do
    // !     writeln(e.Name^, ':', e.Value^);
    // ! // output  a:1  b:2  c:3
    function Fields: TDocVariantFieldsEnumerator;
    /// an enumerator able to compile "for .. in dv.FieldNames do" for objects
    // - returns pointers over all Names[]
    // - don't iterate if the document is an array - so n is never nil:
    // ! var n: PRawUtf8;
    // ! ...
    // !   dv.InitJson('{a:1,b:2,c:3}');
    // !   for n in dv.FieldNames do
    // !     writeln(n^);
    // ! // output  a  b  c
    /// 能够为对象编译“for .. in dv.FieldNames do”的枚举器
     // - 返回所有 Names[] 上的指针
     // - 如果文档是数组，则不要迭代 - 因此 n 永远不会为零：
    // ! var n: PRawUtf8;
    // ! ...
    // !   dv.InitJson('{a:1,b:2,c:3}');
    // !   for n in dv.FieldNames do
    // !     writeln(n^);
    // ! // output  a  b  c
    function FieldNames: TDocVariantFieldNamesEnumerator;
    /// an enumerator able to compile "for .. in dv.FieldValues do" for objects
    // - returns pointers over all Values[]
    // - don't iterate if the document is an array:
    // ! var v: PVariant;
    // ! ...
    // !   dv.InitJson('{a:1,b:2,c:3}');
    // !   for v in dv.FieldValues do
    // !     writeln(v^);
    // ! // output  1  2  3
    /// 能够为对象编译“for .. in dv.FieldValues do”的枚举器
     // - 返回所有 Values[] 上的指针
     // - 如果文档是数组，则不要迭代：
    // ! var v: PVariant;
    // ! ...
    // !   dv.InitJson('{a:1,b:2,c:3}');
    // !   for v in dv.FieldValues do
    // !     writeln(v^);
    // ! // output  1  2  3
    function FieldValues: TDocVariantItemsEnumerator;
    /// an enumerator able to compile "for .. in dv.Items do" for arrays
    // - returns a PVariant over all Values[] of a document array
    // - don't iterate if the document is an object
    // - for instance:
    // ! var v: PVariant;
    // ! ...
    // !    dv.InitArray([1, 3, 3, 4]);
    // !    for v in dv.Items do
    // !      writeln(v^);
    // ! // output  1  2  3  4
    /// 能够为数组编译“for .. in dv.Items do”的枚举器
     // - 返回文档数组的所有 Values[] 上的 PVariant
     // - 如果文档是对象，则不迭代
     // - 例如：
    // ! var v: PVariant;
    // ! ...
    // !    dv.InitArray([1, 3, 3, 4]);
    // !    for v in dv.Items do
    // !      writeln(v^);
    // ! // output  1  2  3  4
    function Items: TDocVariantItemsEnumerator;
    /// an enumerator able to compile "for .. dv.Objects do" for array of objects
    // - returns all Values[] of a document array which are a TDocVariantData
    // - don't iterate if the document is an object, or if an item is not a
    // TDocVariantData:
    // ! var d: PDocVariantData;
    // ! ...
    // !    dv.InitJson('[{a:1,b:1},1,"no object",{a:2,b:2}]');
    // !    for d in dv.Objects do
    // !      writeln(d^.ToJson);
    // ! // output {"a":1,"b":1} and {"a":2,"b":2} only
    // ! // (ignoring 1 and "no object" items)
    /// 能够为对象数组编译“for .. dv.Objects do”的枚举器
     // - 返回文档数组中作为 TDocVariantData 的所有 Values[]
     // - 如果文档是对象，或者项目不是 TDocVariantData，则不要迭代：
    // ! var d: PDocVariantData;
    // ! ...
    // !    dv.InitJson('[{a:1,b:1},1,"no object",{a:2,b:2}]');
    // !    for d in dv.Objects do
    // !      writeln(d^.ToJson);
    // ! // output {"a":1,"b":1} and {"a":2,"b":2} only
    // ! // (ignoring 1 and "no object" items)
    function Objects: TDocVariantObjectsEnumerator;
    {$endif HASITERATORS}

    /// save a document as UTF-8 encoded JSON
    // - will write either a JSON object or array, depending of the internal
    // layout of this instance (i.e. Kind property value)
    // - will write  'null'  if Kind is dvUndefined
    // - implemented as just a wrapper around DocVariantType.ToJson()
    /// 将文档保存为 UTF-8 编码的 JSON
     // - 将写入 JSON 对象或数组，具体取决于此实例的内部布局（即 Kind 属性值）
     // - 如果 Kind 为 dvUndefined，则写入“null”
     // - 作为 DocVariantType.ToJson() 的包装器实现
    function ToJson: RawUtf8; overload;
    /// save a document as UTF-8 encoded JSON
    /// 将文档保存为 UTF-8 编码的 JSON
    function ToJson(const Prefix, Suffix: RawUtf8;
      Format: TTextWriterJsonFormat): RawUtf8; overload;
    /// save a document as UTF-8 encoded JSON file
    // - you may then use InitJsonFromFile() to load and parse this file
    /// 将文档保存为UTF-8编码的JSON文件
     // - 然后您可以使用 InitJsonFromFile() 加载并解析该文件
    procedure SaveToJsonFile(const FileName: TFileName);
    /// save an array of objects as UTF-8 encoded non expanded layout JSON
    // - returned content would be a JSON object in mORMot's TOrmTableJson non
    // expanded format, with reduced JSON size, i.e.
    // $ {"fieldCount":2,"values":["f1","f2","1v1",1v2,"2v1",2v2...],"rowCount":20}
    // - will write '' if Kind is dvUndefined or dvObject
    // - will raise an exception if the array document is not an array of
    // objects with identical field names
    // - can be unserialized using the InitArrayFromResults() method
    /// 将对象数组保存为 UTF-8 编码的非扩展布局 JSON
     // - 返回的内容将是 mORMot 的 TOrmTableJson 非扩展格式的 JSON 对象，并减少 JSON 大小，即
     // $ {"fieldCount":2,"values":["f1","f2","1v1",1v2,"2v1",2v2...],"rowCount":20}
     // - 如果 Kind 是 dvUndefined 或 dvObject，则会写入 ''
     // - 如果数组文档不是具有相同字段名称的对象数组，则会引发异常
     // - 可以使用 InitArrayFromResults() 方法反序列化
    function ToNonExpandedJson: RawUtf8;
    /// save a document as an array of UTF-8 encoded JSON
    // - will expect the document to be a dvArray - otherwise, will raise a
    // EDocVariant exception
    // - will use VariantToUtf8() to populate the result array: as a consequence,
    // any nested custom variant types (e.g. TDocVariant) will be stored as JSON
    /// 将文档保存为UTF-8编码的JSON数组
     // - 期望文档是 dvArray - 否则，将引发 EDocVariant 异常
     // - 将使用 VariantToUtf8() 填充结果数组：因此，任何嵌套的自定义变体类型（例如 TDocVariant）都将存储为 JSON
    procedure ToRawUtf8DynArray(out Result: TRawUtf8DynArray); overload;
    /// save a document as an array of UTF-8 encoded JSON
    // - will expect the document to be a dvArray - otherwise, will raise a
    // EDocVariant exception
    // - will use VariantToUtf8() to populate the result array: as a consequence,
    // any nested custom variant types (e.g. TDocVariant) will be stored as JSON
    /// 将文档保存为UTF-8编码的JSON数组
     // - 期望文档是 dvArray - 否则，将引发 EDocVariant 异常
     // - 将使用 VariantToUtf8() 填充结果数组：因此，任何嵌套的自定义变体类型（例如 TDocVariant）都将存储为 JSON
    function ToRawUtf8DynArray: TRawUtf8DynArray; overload;
      {$ifdef HASINLINE}inline;{$endif}
    /// save a document as an CSV of UTF-8 encoded JSON
    // - will expect the document to be a dvArray - otherwise, will raise a
    // EDocVariant exception
    // - will use VariantToUtf8() to populate the result array: as a consequence,
    // any nested custom variant types (e.g. TDocVariant) will be stored as JSON
    /// 将文档保存为 UTF-8 编码 JSON 的 CSV
     // - 期望文档是 dvArray - 否则，将引发 EDocVariant 异常
     // - 将使用 VariantToUtf8() 填充结果数组：因此，任何嵌套的自定义变体类型（例如 TDocVariant）都将存储为 JSON
    function ToCsv(const Separator: RawUtf8 = ','): RawUtf8;
    /// save a document as UTF-8 encoded Name=Value pairs
    // - will follow by default the .INI format, but you can specify your
    // own expected layout
    /// 将文档保存为 UTF-8 编码的名称=值对
     // - 默认情况下将遵循 .INI 格式，但您可以指定自己的预期布局
    procedure ToTextPairsVar(out result: RawUtf8;
      const NameValueSep: RawUtf8 = '='; const ItemSep: RawUtf8 = #13#10;
      Escape: TTextWriterKind = twJsonEscape);
    /// save a document as UTF-8 encoded Name=Value pairs
    // - will follow by default the .INI format, but you can specify your
    // own expected layout
    /// 将文档保存为 UTF-8 编码的名称=值对
     // - 默认情况下将遵循 .INI 格式，但您可以指定自己的预期布局
    function ToTextPairs(const NameValueSep: RawUtf8 = '=';
      const ItemSep: RawUtf8 = #13#10;
      Escape: TTextWriterKind = twJsonEscape): RawUtf8;
       {$ifdef HASINLINE}inline;{$endif}
    /// save an array document as an array of TVarRec, i.e. an array of const
    // - will expect the document to be a dvArray - otherwise, will raise a
    // EDocVariant exception
    // - values will be passed by referenced as vtVariant to @VValue[ndx]
    // - would allow to write code as such:
    // !  Doc.InitArray(['one',2,3]);
    // !  Doc.ToArrayOfConst(vr);
    // !  s := FormatUtf8('[%,%,%]',vr,[],true);
    // !  // here s='[one,2,3]') since % would be replaced by Args[] parameters
    // !  s := FormatUtf8('[?,?,?]',[],vr,true);
    // !  // here s='["one",2,3]') since ? would be escaped by Params[] parameters
    /// 将数组文档保存为 TVarRec 数组，即 const 数组
     // - 期望文档是 dvArray - 否则，将引发 EDocVariant 异常
     // - 值将通过引用为 vtVariant 传递给 @VValue[ndx]
     // - 允许编写这样的代码：
    // !  Doc.InitArray(['one',2,3]);
    // !  Doc.ToArrayOfConst(vr);
    // !  s := FormatUtf8('[%,%,%]',vr,[],true);
    // !  // here s='[one,2,3]') since % would be replaced by Args[] parameters
    // !  s := FormatUtf8('[?,?,?]',[],vr,true);
    // !  // here s='["one",2,3]') since ? would be escaped by Params[] parameters
    procedure ToArrayOfConst(out Result: TTVarRecDynArray); overload;
    /// save an array document as an array of TVarRec, i.e. an array of const
    // - will expect the document to be a dvArray - otherwise, will raise a
    // EDocVariant exception
    // - values will be passed by referenced as vtVariant to @VValue[ndx]
    // - would allow to write code as such:
    // !  Doc.InitArray(['one',2,3]);
    // !  s := FormatUtf8('[%,%,%]',Doc.ToArrayOfConst,[],true);
    // !  // here s='[one,2,3]') since % would be replaced by Args[] parameters
    // !  s := FormatUtf8('[?,?,?]',[],Doc.ToArrayOfConst,true);
    // !  // here s='["one",2,3]') since ? would be escaped by Params[] parameters
    /// 将数组文档保存为 TVarRec 数组，即 const 数组
     // - 期望文档是 dvArray - 否则，将引发 EDocVariant 异常
     // - 值将通过引用为 vtVariant 传递给 @VValue[ndx]
     // - 允许编写这样的代码：
    // !  Doc.InitArray(['one',2,3]);
    // !  s := FormatUtf8('[%,%,%]',Doc.ToArrayOfConst,[],true);
    // !  // here s='[one,2,3]') since % would be replaced by Args[] parameters
    // !  s := FormatUtf8('[?,?,?]',[],Doc.ToArrayOfConst,true);
    // !  // here s='["one",2,3]') since ? would be escaped by Params[] parameters
    function ToArrayOfConst: TTVarRecDynArray; overload;
      {$ifdef HASINLINE}inline;{$endif}
    /// save an object document as an URI-encoded list of parameters
    // - object field names should be plain ASCII-7 RFC compatible identifiers
    // (0..9a..zA..Z_.~), otherwise their values are skipped
    /// 将对象文档保存为 URI 编码的参数列表
     // - 对象字段名称应该是纯 ASCII-7 RFC 兼容标识符 (0..9a..zA..Z_.~)，否则它们的值将被跳过
    function ToUrlEncode(const UriRoot: RawUtf8): RawUtf8;

    /// returns true if this is not a true TDocVariant, or Count equals 0
    /// 如果这不是一个真正的 TDocVariant，或者 Count 等于 0，则返回 true
    function IsVoid: boolean;
      {$ifdef HASINLINE}inline;{$endif}
    /// find an item index in this document from its name
    // - search will follow dvoNameCaseSensitive option of this document
    // - lookup the value by name for an object document, or accept an integer
    // text as index for an array document
    // - returns -1 if not found
    /// 根据名称查找该文档中的项目索引
     // - 搜索将遵循本文档的 dvoNameCaseSensitive 选项
     // - 按对象文档的名称查找值，或接受整数文本作为数组文档的索引
     // - 如果没有找到则返回-1
    function GetValueIndex(const aName: RawUtf8): integer; overload;
      {$ifdef HASINLINE}inline;{$endif}
    /// find an item index in this document from its name
    // - lookup the value by name for an object document, or accept an integer
    // text as index for an array document
    // - returns -1 if not found
    /// 根据名称查找该文档中的项目索引
     // - 按对象文档的名称查找值，或接受整数文本作为数组文档的索引
     // - 如果没有找到则返回-1
    function GetValueIndex(aName: PUtf8Char; aNameLen: PtrInt;
      aCaseSensitive: boolean): integer; overload;
    /// find an item in this document, and returns its value
    // - raise an EDocVariant if not found and dvoReturnNullForUnknownProperty
    // is not set in Options (in this case, it will return Null)
    /// 在这个文档中查找一个项目，并返回它的值
     // - 如果未找到且选项中未设置 dvoReturnNullForUnknownProperty，则引发 EDocVariant（在这种情况下，它将返回 Null）
    function GetValueOrRaiseException(const aName: RawUtf8): variant;
    /// find an item in this document, and returns its value
    // - return the supplied default if aName is not found, or if the instance
    // is not a TDocVariant
    /// 在这个文档中查找一个项目，并返回它的值
     // - 如果未找到 aName，或者实例不是 TDocVariant，则返回提供的默认值
    function GetValueOrDefault(const aName: RawUtf8;
      const aDefault: variant): variant;
    /// find an item in this document, and returns its value
    // - return null if aName is not found, or if the instance is not a TDocVariant
    /// 在这个文档中查找一个项目，并返回它的值
     // - 如果未找到 aName，或者实例不是 TDocVariant，则返回 null
    function GetValueOrNull(const aName: RawUtf8): variant;
    /// find an item in this document, and returns its value
    // - return a cleared variant if aName is not found, or if the instance is
    // not a TDocVariant
    /// 在这个文档中查找一个项目，并返回它的值
     // - 如果未找到 aName，或者实例不是 TDocVariant，则返回已清除的变体
    function GetValueOrEmpty(const aName: RawUtf8): variant;
    /// find an item in this document, and returns its value as enumerate
    // - return false if aName is not found, if the instance is not a TDocVariant,
    // or if the value is not a string corresponding to the supplied enumerate
    // - return true if the name has been found, and aValue stores the value
    // - will call Delete() on the found entry, if aDeleteFoundEntry is true
    /// 在此文档中查找一个项目，并以枚举形式返回其值
     // - 如果未找到 aName、实例不是 TDocVariant、或者值不是与提供的枚举相对应的字符串，则返回 false
     // - 如果已找到名称且 aValue 存储该值，则返回 true
     // - 如果 aDeleteFoundEntry 为 true，将对找到的条目调用 Delete()
    function GetValueEnumerate(const aName: RawUtf8; aTypeInfo: PRttiInfo;
      out aValue; aDeleteFoundEntry: boolean = false): boolean;
    /// returns a JSON object containing all properties matching the
    // first characters of the supplied property name
    // - returns null if the document is not a dvObject
    // - will use IdemPChar(), so search would be case-insensitive
    /// 返回一个 JSON 对象，其中包含与所提供属性名称的第一个字符匹配的所有属性
     // - 如果文档不是 dvObject，则返回 null
     // - 将使用 IdemPChar()，因此搜索不区分大小写
    function GetJsonByStartName(const aStartName: RawUtf8): RawUtf8;
    /// find an item in this document, and returns its value as TVarData
    // - return false if aName is not found, or if the instance is not a TDocVariant
    // - return true and set aValue if the name has been found
    // - will use simple loop lookup to identify the name, unless aSortedCompare is
    // set, and would let use a faster O(log(n)) binary search after a SortByName()
    /// 在此文档中查找一个项目，并将其值作为 TVarData 返回
     // - 如果未找到 aName，或者实例不是 TDocVariant，则返回 false
     // - 如果已找到名称，则返回 true 并设置 aValue
     // - 将使用简单循环查找来识别名称，除非设置了 aSortedCompare，并且将在 SortByName() 之后使用更快的 O(log(n)) 二分搜索
    function GetVarData(const aName: RawUtf8; var aValue: TVarData;
      aSortedCompare: TUtf8Compare = nil): boolean; overload;
      {$ifdef HASINLINE}inline;{$endif}
    /// find an item in this document, and returns its value as TVarData pointer
    // - return nil if aName is not found, or if the instance is not a TDocVariant
    // - return a pointer to the value if the name has been found, and optionally
    // fill aFoundIndex^ with its index in Values[]
    // - after a SortByName(aSortedCompare), could use faster binary search
    /// 在此文档中查找一项，并将其值作为 TVarData 指针返回
     // - 如果未找到 aName，或者实例不是 TDocVariant，则返回 nil
     // - 如果已找到名称，则返回指向该值的指针，并可选择使用其在 Values[] 中的索引填充 aFoundIndex^
     // - 在 SortByName(aSortedCompare) 之后，可以使用更快的二分搜索
    function GetVarData(const aName: RawUtf8; aSortedCompare: TUtf8Compare = nil;
      aFoundIndex: PInteger = nil): PVarData; overload;
    /// find an item in this document, and returns its value as boolean
    // - return false if aName is not found, or if the instance is not a TDocVariant
    // - return true if the name has been found, and aValue stores the value
    // - after a SortByName(aSortedCompare), could use faster binary search
    // - consider using B[] property if you want simple read/write typed access
    /// 在此文档中查找一个项目，并将其值返回为布尔值
     // - 如果未找到 aName，或者实例不是 TDocVariant，则返回 false
     // - 如果已找到名称且 aValue 存储该值，则返回 true
     // - 在 SortByName(aSortedCompare) 之后，可以使用更快的二分搜索
     // - 如果您想要简单的读/写类型访问，请考虑使用 B[] 属性
    function GetAsBoolean(const aName: RawUtf8; out aValue: boolean;
      aSortedCompare: TUtf8Compare = nil): boolean;
    /// find an item in this document, and returns its value as integer
    // - return false if aName is not found, or if the instance is not a TDocVariant
    // - return true if the name has been found, and aValue stores the value
    // - after a SortByName(aSortedCompare), could use faster binary search
    // - consider using I[] property if you want simple read/write typed access
    /// 在此文档中查找一个项目，并以整数形式返回其值
     // - 如果未找到 aName，或者实例不是 TDocVariant，则返回 false
     // - 如果已找到名称且 aValue 存储该值，则返回 true
     // - 在 SortByName(aSortedCompare) 之后，可以使用更快的二分搜索
     // - 如果您想要简单的读/写类型访问，请考虑使用 I[] 属性
    function GetAsInteger(const aName: RawUtf8; out aValue: integer;
      aSortedCompare: TUtf8Compare = nil): boolean;
    /// find an item in this document, and returns its value as integer
    // - return false if aName is not found, or if the instance is not a TDocVariant
    // - return true if the name has been found, and aValue stores the value
    // - after a SortByName(aSortedCompare), could use faster binary search
    // - consider using I[] property if you want simple read/write typed access
    /// 在此文档中查找一个项目，并以整数形式返回其值
     // - 如果未找到 aName，或者实例不是 TDocVariant，则返回 false
     // - 如果已找到名称且 aValue 存储该值，则返回 true
     // - 在 SortByName(aSortedCompare) 之后，可以使用更快的二分搜索
     // - 如果您想要简单的读/写类型访问，请考虑使用 I[] 属性
    function GetAsInt64(const aName: RawUtf8; out aValue: Int64;
      aSortedCompare: TUtf8Compare = nil): boolean;
    /// find an item in this document, and returns its value as floating point
    // - return false if aName is not found, or if the instance is not a TDocVariant
    // - return true if the name has been found, and aValue stores the value
    // - after a SortByName(aSortedCompare), could use faster binary search
    // - consider using D[] property if you want simple read/write typed access
    /// 在此文档中查找一项，并以浮点形式返回其值
     // - 如果未找到 aName，或者实例不是 TDocVariant，则返回 false
     // - 如果已找到名称且 aValue 存储该值，则返回 true
     // - 在 SortByName(aSortedCompare) 之后，可以使用更快的二分搜索
     // - 如果您想要简单的读/写类型访问，请考虑使用 D[] 属性
    function GetAsDouble(const aName: RawUtf8; out aValue: double;
      aSortedCompare: TUtf8Compare = nil): boolean;
    /// find an item in this document, and returns its value as RawUtf8
    // - return false if aName is not found, or if the instance is not a TDocVariant
    // - return true if the name has been found, and aValue stores the value
    // - after a SortByName(aSortedCompare), could use faster binary search
    // - consider using U[] property if you want simple read/write typed access
    /// 在此文档中查找一项，并以 RawUtf8 形式返回其值
     // - 如果未找到 aName，或者实例不是 TDocVariant，则返回 false
     // - 如果已找到名称且 aValue 存储该值，则返回 true
     // - 在 SortByName(aSortedCompare) 之后，可以使用更快的二分搜索
     // - 如果您想要简单的读/写类型访问，请考虑使用 U[] 属性
    function GetAsRawUtf8(const aName: RawUtf8; out aValue: RawUtf8;
      aSortedCompare: TUtf8Compare = nil): boolean;
    /// find an item in this document, and returns its value as a TDocVariantData
    // - return false if aName is not found, or if the instance is not a TDocVariant
    // - return true if the name has been found and points to a TDocVariant:
    // then aValue stores a pointer to the value
    // - after a SortByName(aSortedCompare), could use faster binary search
    /// 在此文档中查找一个项目，并以 TDocVariantData 形式返回其值
     // - 如果未找到 aName，或者实例不是 TDocVariant，则返回 false
     // - 如果已找到名称并指向 TDocVariant，则返回 true：然后 aValue 存储指向该值的指针
     // - 在 SortByName(aSortedCompare) 之后，可以使用更快的二分搜索
    function GetAsDocVariant(const aName: RawUtf8; out aValue: PDocVariantData;
      aSortedCompare: TUtf8Compare = nil): boolean;
    /// find a non-void array item in this document, and returns its value
    // - return false if aName is not found, or if not a TDocVariant array
    // - return true if the name was found as non-void array and set to aArray
    // - after a SortByName(aSortedCompare), could use faster binary search
    /// 在本文档中查找非void数组项，并返回其值
     // - 如果未找到 aName，或者不是 TDocVariant 数组，则返回 false
     // - 如果发现名称为非 void 数组并设置为 aArray，则返回 true
     // - 在 SortByName(aSortedCompare) 之后，可以使用更快的二分搜索
    function GetAsArray(const aName: RawUtf8; out aArray: PDocVariantData;
      aSortedCompare: TUtf8Compare = nil): boolean;
    /// find a non-void object item in this document, and returns its value
    // - return false if aName is not found, or if not a TDocVariant object
    // - return true if the name was found as non-void object and set to aObject
    // - after a SortByName(aSortedCompare), could use faster binary search
    /// 在这个文档中找到一个非void对象项，并返回它的值
     // - 如果未找到 aName，或者不是 TDocVariant 对象，则返回 false
     // - 如果名称被发现为非 void 对象并设置为 aObject，则返回 true
     // - 在 SortByName(aSortedCompare) 之后，可以使用更快的二分搜索
    function GetAsObject(const aName: RawUtf8; out aObject: PDocVariantData;
      aSortedCompare: TUtf8Compare = nil): boolean;
    /// find an item in this document, and returns its value as a TDocVariantData
    // - returns a void TDocVariant if aName is not a document
    // - after a SortByName(aSortedCompare), could use faster binary search
    // - consider using O[] or A[] properties if you want simple read-only
    // access, or O_[] or A_[] properties if you want the ability to add
    // a missing object or array in the document
    /// 在此文档中查找一个项目，并以 TDocVariantData 形式返回其值
     // - 如果 aName 不是文档，则返回 void TDocVariant
     // - 在 SortByName(aSortedCompare) 之后，可以使用更快的二分搜索
     // - 如果您想要简单的只读访问，请考虑使用 O[] 或 A[] 属性；如果您希望能够在文档中添加缺少的对象或数组，请考虑使用 O_[] 或 A_[] 属性
    function GetAsDocVariantSafe(const aName: RawUtf8;
      aSortedCompare: TUtf8Compare = nil): PDocVariantData;
    /// find an item in this document, and returns pointer to its value
    // - return false if aName is not found
    // - return true if the name has been found: then aValue stores a pointer
    // to the value
    // - after a SortByName(aSortedCompare), could use faster binary search
    /// 在此文档中查找一项，并返回指向其值的指针
     // - 如果未找到 aName，则返回 false
     // - 如果已找到名称，则返回 true：然后 aValue 存储指向该值的指针
     // - 在 SortByName(aSortedCompare) 之后，可以使用更快的二分搜索
    function GetAsPVariant(const aName: RawUtf8; out aValue: PVariant;
      aSortedCompare: TUtf8Compare = nil): boolean; overload;
       {$ifdef HASINLINE}inline;{$endif}
    /// find an item in this document, and returns pointer to its value
    // - lookup the value by aName/aNameLen for an object document, or accept
    // an integer text as index for an array document
    // - return nil if aName is not found, or if the instance is not a TDocVariant
    // - return a pointer to the stored variant, if the name has been found
    /// 在此文档中查找一项，并返回指向其值的指针
     // - 通过 aName/aNameLen 查找对象文档的值，或接受
     // 整数文本作为数组文档的索引
     // - 如果未找到 aName，或者实例不是 TDocVariant，则返回 nil
     // - 如果已找到名称，则返回指向存储变体的指针
    function GetAsPVariant(aName: PUtf8Char; aNameLen: PtrInt): PVariant; overload;
      {$ifdef HASINLINE}inline;{$endif}
    /// retrieve a value, given its path
    // - path is defined as a dotted name-space, e.g. 'doc.glossary.title'
    // - it will return Unassigned if there is no item at the supplied aPath
    // - you can set e.g. aPathDelim = '/' to search e.g. for 'parent/child'
    // - see also the P[] property if the default aPathDelim = '.' is enough
    /// 检索一个值，给定其路径
     // - 路径被定义为点状命名空间，例如 '文档.词汇表.标题'
     // - 如果提供的 aPath 中没有项目，它将返回 Unassigned
     // - 你可以设置例如 aPathDelim = '/' 进行搜索，例如 对于“父母/孩子”
     // - 如果默认 aPathDelim = '.'，另请参阅 P[] 属性 足够
    function GetValueByPath(
      const aPath: RawUtf8; aPathDelim: AnsiChar = '.'): variant; overload;
    /// retrieve a value, given its path
    // - path is defined as a dotted name-space, e.g. 'doc.glossary.title'
    // - returns FALSE if there is no item at the supplied aPath
    // - returns TRUE and set the found value in aValue
    // - you can set e.g. aPathDelim = '/' to search e.g. for 'parent/child'
    // - see also the P[] property if the default aPathDelim = '.' is enough
    /// 检索一个值，给定其路径
     // - 路径被定义为点状命名空间，例如 '文档.词汇表.标题'
     // - 如果提供的 aPath 处没有项目，则返回 FALSE
     // - 返回 TRUE 并将找到的值设置在 aValue 中
     // - 你可以设置例如 aPathDelim = '/' 进行搜索，例如 对于“父母/孩子”
     // - 如果默认 aPathDelim = '.'，另请参阅 P[] 属性 足够
    function GetValueByPath(const aPath: RawUtf8; out aValue: variant;
      aPathDelim: AnsiChar = '.'): boolean; overload;
    /// retrieve a value, given its path
    // - path is defined as a list of names, e.g. ['doc','glossary','title']
    // - returns Unassigned if there is no item at the supplied aPath
    // - this method will only handle nested TDocVariant values: use the
    // slightly slower GetValueByPath() overloaded method, if any nested object
    // may be of another type (e.g. a TBsonVariant)
    /// 检索一个值，给定其路径
     // - 路径被定义为名称列表，例如 ['文档'，'术语表'，'标题']
     // - 如果提供的 aPath 处没有项目，则返回 Unassigned
     // - 此方法将仅处理嵌套的 TDocVariant 值：如果任何嵌套对象可能是其他类型（例如 TBsonVariant），请使用稍慢的 GetValueByPath() 重载方法
    function GetValueByPath(
      const aDocVariantPath: array of RawUtf8): variant; overload;
    /// retrieve a reference to a value, given its path
    // - path is defined as a dotted name-space, e.g. 'doc.glossary.title'
    // - if the supplied aPath does not match any object, it will return nil
    // - if aPath is found, returns a pointer to the corresponding value
    // - you can set e.g. aPathDelim = '/' to search e.g. for 'parent/child'
    /// 在给定路径的情况下检索对值的引用
     // - 路径被定义为点状命名空间，例如 '文档.词汇表.标题'
     // - 如果提供的 aPath 与任何对象都不匹配，它将返回 nil
     // - 如果找到aPath，则返回指向相应值的指针
     // - 你可以设置例如 aPathDelim = '/' 进行搜索，例如 对于“父母/孩子”
    function GetPVariantByPath(
      const aPath: RawUtf8; aPathDelim: AnsiChar = '.'): PVariant;
    /// retrieve a reference to a TDocVariant, given its path
    // - path is defined as a dotted name-space, e.g. 'doc.glossary.title'
    // - if the supplied aPath does not match any object, it will return false
    // - if aPath stores a valid TDocVariant, returns true and a pointer to it
    // - you can set e.g. aPathDelim = '/' to search e.g. for 'parent/child'
    /// 在给定路径的情况下检索对 TDocVariant 的引用
     // - 路径被定义为点状命名空间，例如 '文档.词汇表.标题'
     // - 如果提供的 aPath 与任何对象都不匹配，它将返回 false
     // - 如果 aPath 存储有效的 TDocVariant，则返回 true 和指向它的指针
     // - 你可以设置例如 aPathDelim = '/' 进行搜索，例如 对于“父母/孩子”
    function GetDocVariantByPath(const aPath: RawUtf8;
      out aValue: PDocVariantData; aPathDelim: AnsiChar = '.'): boolean;
    /// retrieve a dvObject in the dvArray, from a property value
    // - {aPropName:aPropValue} will be searched within the stored array,
    // and the corresponding item will be copied into Dest, on match
    // - returns FALSE if no match is found, TRUE if found and copied
    // - create a copy of the variant by default, unless DestByRef is TRUE
    // - will call VariantEquals() for value comparison
    /// 从属性值中检索 dvArray 中的 dvObject
     // - {aPropName:aPropValue} 将在存储的数组中搜索，匹配时相应的项将被复制到 Dest 中
     // - 如果未找到匹配则返回 FALSE，如果找到并复制则返回 TRUE
     // - 默认情况下创建变体的副本，除非 DestByRef 为 TRUE
     // - 将调用 VariantEquals() 进行值比较
    function GetItemByProp(const aPropName, aPropValue: RawUtf8;
      aPropValueCaseSensitive: boolean; var Dest: variant;
      DestByRef: boolean = false): boolean;
    /// retrieve a reference to a dvObject in the dvArray, from a property value
    // - {aPropName:aPropValue} will be searched within the stored array,
    // and the corresponding item will be copied into Dest, on match
    // - returns FALSE if no match is found, TRUE if found and copied by reference
    /// 从属性值中检索 dvArray 中 dvObject 的引用
     // - {aPropName:aPropValue} 将在存储的数组中搜索，匹配时相应的项将被复制到 Dest 中
     // - 如果未找到匹配项，则返回 FALSE；如果找到匹配项并通过引用复制，则返回 TRUE
    function GetDocVariantByProp(const aPropName, aPropValue: RawUtf8;
      aPropValueCaseSensitive: boolean; out Dest: PDocVariantData): boolean;
    /// find an item in this document, and returns its value
    // - raise an EDocVariant if not found and dvoReturnNullForUnknownProperty
    // is not set in Options (in this case, it will return Null)
    // - create a copy of the variant by default, unless DestByRef is TRUE
    /// 在这个文档中查找一个项目，并返回它的值
     // - 如果未找到且选项中未设置 dvoReturnNullForUnknownProperty，则引发 EDocVariant（在这种情况下，它将返回 Null）
     // - 默认情况下创建变体的副本，除非 DestByRef 为 TRUE
    function RetrieveValueOrRaiseException(aName: PUtf8Char; aNameLen: integer;
      aCaseSensitive: boolean; var Dest: variant; DestByRef: boolean): boolean; overload;
    /// retrieve an item in this document from its index, and returns its value
    // - raise an EDocVariant if the supplied Index is not in the 0..Count-1
    // range and dvoReturnNullForUnknownProperty is set in Options
    // - create a copy of the variant by default, unless DestByRef is TRUE
    /// 从其索引中检索此文档中的项目，并返回其值
     // - 如果提供的索引不在 0..Count-1 范围内并且在选项中设置了 dvoReturnNullForUnknownProperty，则引发 EDocVariant
     // - 默认情况下创建变体的副本，除非 DestByRef 为 TRUE
    procedure RetrieveValueOrRaiseException(Index: integer;
     var Dest: variant; DestByRef: boolean); overload;
    /// retrieve an item in this document from its index, and returns its Name
    // - raise an EDocVariant if the supplied Index is not in the 0..Count-1
    // range and dvoReturnNullForUnknownProperty is set in Options
    /// 从其索引中检索此文档中的项目，并返回其名称
     // - 如果提供的索引不在 0..Count-1 范围内并且在选项中设置了 dvoReturnNullForUnknownProperty，则引发 EDocVariant
    procedure RetrieveNameOrRaiseException(Index: integer; var Dest: RawUtf8);
    /// returns a TDocVariant object containing all properties matching the
    // first characters of the supplied property name
    // - returns null if the document is not a dvObject
    // - will use IdemPChar(), so search would be case-insensitive
    /// 返回一个 TDocVariant 对象，其中包含与所提供属性名称的第一个字符匹配的所有属性
     // - 如果文档不是 dvObject，则返回 null
     // - 将使用 IdemPChar()，因此搜索不区分大小写
    function GetValuesByStartName(const aStartName: RawUtf8;
      TrimLeftStartName: boolean = false): variant;
    /// set an item in this document from its index
    // - raise an EDocVariant if the supplied Index is not in 0..Count-1 range
    /// 从文档的索引中设置一个项目
     // - 如果提供的索引不在 0..Count-1 范围内，则引发 EDocVariant
    procedure SetValueOrRaiseException(Index: integer; const NewValue: variant);
    /// set a value, given its path
    // - path is defined as a dotted name-space, e.g. 'doc.glossary.title'
    // - aCreateIfNotExisting=true will force missing nested objects creation
    // - returns FALSE if there is no item to be set at the supplied aPath
    // - returns TRUE and set the found value in aValue
    // - you can set e.g. aPathDelim = '/' to search e.g. for 'parent/child'
    /// 设置一个值，给定其路径
     // - 路径被定义为点状命名空间，例如 '文档.词汇表.标题'
     // - aCreateIfNotExisting=true 将强制创建缺失的嵌套对象
     // - 如果在提供的 aPath 处没有要设置的项目，则返回 FALSE
     // - 返回 TRUE 并将找到的值设置在 aValue 中
     // - 你可以设置例如 aPathDelim = '/' 进行搜索，例如 对于“父母/孩子”
    function SetValueByPath(const aPath: RawUtf8; const aValue: variant;
      aCreateIfNotExisting: boolean = false; aPathDelim: AnsiChar = '.'): boolean;

    /// add a value in this document
    // - if aName is set, if dvoCheckForDuplicatedNames option is set, any
    // existing duplicated aName will raise an EDocVariant; if instance's
    // kind is dvArray and aName is defined, it will raise an EDocVariant
    // - aName may be '' e.g. if you want to store an array: in this case,
    // dvoCheckForDuplicatedNames option should not be set; if instance's Kind
    // is dvObject, it will raise an EDocVariant exception
    // - if aValueOwned is true, then the supplied aValue will be assigned to
    // the internal values - by default, it will use SetVariantByValue()
    // - you can therefore write e.g.:
    // ! TDocVariant.New(aVariant);
    // ! Assert(TDocVariantData(aVariant).Kind=dvUndefined);
    // ! TDocVariantData(aVariant).AddValue('name','John');
    // ! Assert(TDocVariantData(aVariant).Kind=dvObject);
    // - you can specify an optional index in the array where to insert
    // - returns the index of the corresponding newly added value
    /// 在此文档中添加一个值
     // - 如果设置了 aName，如果设置了 dvoCheckForDuplicatedNames 选项，则任何现有的重复 aName 将引发 EDocVariant； 如果实例的种类是 dvArray 并且定义了 aName，它将引发一个 EDocVariant
     // - aName 可能是 '' 例如 如果要存储数组：在这种情况下，不应设置 dvoCheckForDuplicatedNames 选项； 如果实例的 Kind 是 dvObject，它将引发 EDocVariant 异常
     // - 如果 aValueOwned 为 true，则提供的 aValue 将被分配给内部值 - 默认情况下，它将使用 SetVariantByValue()
     // - 因此你可以写例如：
    // ! TDocVariant.New(aVariant);
    // ! Assert(TDocVariantData(aVariant).Kind=dvUndefined);
    // ! TDocVariantData(aVariant).AddValue('name','John');
    // ! Assert(TDocVariantData(aVariant).Kind=dvObject);
     // - 您可以指定数组中插入位置的可选索引
     // - 返回对应新添加值的索引
    function AddValue(const aName: RawUtf8; const aValue: variant;
      aValueOwned: boolean = false; aIndex: integer = -1): integer; overload;
    /// add a value in this document
    // - overloaded function accepting a UTF-8 encoded buffer for the name
    /// 在此文档中添加一个值
     // - 接受 UTF-8 编码缓冲区作为名称的重载函数
    function AddValue(aName: PUtf8Char; aNameLen: integer; const aValue: variant;
      aValueOwned: boolean = false; aIndex: integer = -1): integer; overload;
    /// add a value in this document, or update an existing entry
    // - if instance's Kind is dvArray, it will raise an EDocVariant exception
    // - any existing Name would be updated with the new Value, unless
    // OnlyAddMissing is set to TRUE, in which case existing values would remain
    // - returns the index of the corresponding value, which may be just added
    /// 在此文档中添加值，或更新现有条目
     // - 如果实例的 Kind 是 dvArray，它将引发 EDocVariant 异常
     // - 任何现有名称都将使用新值进行更新，除非 OnlyAddMissing 设置为 TRUE，在这种情况下现有值将保留
     // - 返回对应值的索引，该值可能是刚刚添加的
    function AddOrUpdateValue(const aName: RawUtf8; const aValue: variant;
      wasAdded: PBoolean = nil; OnlyAddMissing: boolean = false): integer;
    /// add a value in this document, from its text representation
    // - this function expects a UTF-8 text for the value, which would be
    // converted to a variant number, if possible (as varInt/varInt64/varCurrency
    // and/or as varDouble is AllowVarDouble is set)
    // - if Update=TRUE, will set the property, even if it is existing
    /// 从文档的文本表示中添加一个值
     // - 此函数需要一个 UTF-8 文本作为值，如果可能的话，该文本将被转换为变体数字（如 varInt/varInt64/varCurrency 和/或 varDouble 被设置为AllowVarDouble）
     // - 如果 Update=TRUE，将设置该属性，即使它已存在
    function AddValueFromText(const aName, aValue: RawUtf8;
      DoUpdate: boolean = false; AllowVarDouble: boolean = false): integer;
    /// add some properties to a TDocVariantData dvObject
    // - data is supplied two by two, as Name,Value pairs
    // - caller should ensure that Kind=dvObject, otherwise it won't do anything
    // - any existing Name would be duplicated - use Update() if you want to
    // replace any existing value
    /// 添加一些属性到 TDocVariantData dvObject
     // - 数据以名称、值对的形式两两提供
     // - 调用者应确保 Kind=dvObject，否则它不会执行任何操作
     // - 任何现有名称都会重复 - 如果要替换任何现有值，请使用 Update()
    procedure AddNameValuesToObject(const NameValuePairs: array of const);
    /// merge some properties to a TDocVariantData dvObject
    // - data is supplied two by two, as Name,Value pairs
    // - caller should ensure that Kind=dvObject, otherwise it won't do anything
    // - any existing Name would be updated with the new Value
    /// 将一些属性合并到 TDocVariantData dvObject
     // - 数据以名称、值对的形式两两提供
     // - 调用者应确保 Kind=dvObject，否则它不会执行任何操作
     // - 任何现有名称都将更新为新值
    procedure Update(const NameValuePairs: array of const);
    {$ifndef PUREMORMOT2}
    /// deprecated method which redirects to Update()
    /// 已弃用的重定向到 Update() 的方法
    procedure AddOrUpdateNameValuesToObject(const NameValuePairs: array of const);
    {$endif PUREMORMOT2}
    /// merge some TDocVariantData dvObject properties to a TDocVariantData dvObject
    // - data is supplied two by two, as Name,Value pairs
    // - caller should ensure that both variants have Kind=dvObject, otherwise
    // it won't do anything
    // - any existing Name would be updated with the new Value, unless
    // OnlyAddMissing is set to TRUE, in which case existing values would remain
    /// 将一些 TDocVariantData dvObject 属性合并到 TDocVariantData dvObject
     // - 数据以名称、值对的形式两两提供
     // - 调用者应确保两个变体都有 Kind=dvObject，否则它不会执行任何操作
     // - 任何现有名称都将使用新值进行更新，除非 OnlyAddMissing 设置为 TRUE，在这种情况下现有值将保留
    procedure AddOrUpdateObject(const NewValues: variant;
      OnlyAddMissing: boolean = false; RecursiveUpdate: boolean = false);
    /// add a value to this document, handled as array
    // - if instance's Kind is dvObject, it will raise an EDocVariant exception
    // - you can therefore write e.g.:
    // ! TDocVariant.New(aVariant);
    // ! Assert(TDocVariantData(aVariant).Kind=dvUndefined);
    // ! TDocVariantData(aVariant).AddItem('one');
    // ! Assert(TDocVariantData(aVariant).Kind=dvArray);
    // - you can specify an optional index in the array where to insert
    // - returns the index of the corresponding newly added item
    /// 向该文档添加一个值，作为数组处理
     // - 如果实例的 Kind 是 dvObject，它将引发 EDocVariant 异常
     // - 因此你可以写例如：
    // ! TDocVariant.New(aVariant);
    // ! Assert(TDocVariantData(aVariant).Kind=dvUndefined);
    // ! TDocVariantData(aVariant).AddItem('one');
    // ! Assert(TDocVariantData(aVariant).Kind=dvArray);
     // - 您可以指定数组中插入位置的可选索引
     // - 返回对应新添加项的索引
    function AddItem(const aValue: variant; aIndex: integer = -1): integer; overload;
    /// add a TDocVariant value to this document, handled as array
    /// 将 TDocVariant 值添加到此文档，作为数组处理
    function AddItem(const aValue: TDocVariantData; aIndex: integer = -1): integer; overload;
    /// add a value to this document, handled as array, from its text representation
    // - this function expects a UTF-8 text for the value, which would be
    // converted to a variant number, if possible (as varInt/varInt64/varCurrency
    // unless AllowVarDouble is set)
    // - if instance's Kind is dvObject, it will raise an EDocVariant exception
    // - you can specify an optional index in the array where to insert
    // - returns the index of the corresponding newly added item
    /// 从文档的文本表示中添加一个值，作为数组处理
     // - 此函数需要值的 UTF-8 文本，如果可能的话，该文本将转换为变体编号（如 varInt/varInt64/varCurrency，除非设置了 AllowVarDouble）
     // - 如果实例的 Kind 是 dvObject，它将引发 EDocVariant 异常
     // - 您可以指定数组中插入位置的可选索引
     // - 返回对应新添加项的索引
    function AddItemFromText(const aValue: RawUtf8;
      AllowVarDouble: boolean = false; aIndex: integer = -1): integer;
    /// add a RawUtf8 value to this document, handled as array
    // - if instance's Kind is dvObject, it will raise an EDocVariant exception
    // - you can specify an optional index in the array where to insert
    // - returns the index of the corresponding newly added item
    /// 将 RawUtf8 值添加到此文档，作为数组处理
     // - 如果实例的 Kind 是 dvObject，它将引发 EDocVariant 异常
     // - 您可以指定数组中插入位置的可选索引
     // - 返回对应新添加项的索引
    function AddItemText(const aValue: RawUtf8; aIndex: integer = -1): integer;
    /// add one or several values to this document, handled as array
    // - if instance's Kind is dvObject, it will raise an EDocVariant exception
    /// 添加一个或多个值到此文档，作为数组处理
     // - 如果实例的 Kind 是 dvObject，它将引发 EDocVariant 异常
    procedure AddItems(const aValue: array of const);
    /// add one object document to this document
    // - if the document is an array, keep aName=''
    // - if the document is an object, set the new object property as aName
    // - new object will keep the same options as this document
    // - slightly faster than AddItem(_Obj(...)) or AddValue(aName, _Obj(...))
    /// 向该文档添加一个对象文档
     // - 如果文档是数组，则保留 aName=''
     // - 如果文档是一个对象，则将新对象属性设置为 aName
     // - 新对象将保留与本文档相同的选项
     // - 比 AddItem(_Obj(...)) 或 AddValue(aName, _Obj(...)) 稍快
    procedure AddObject(const aNameValuePairs: array of const;
      const aName: RawUtf8 = '');
    /// add one or several values from another document
    // - supplied document should be of the same kind than the current one,
    // otherwise nothing is added
    // - for an object, dvoCheckForDuplicatedNames flag is used: use
    // AddOrUpdateFrom() to force objects merging
    /// 添加另一个文档中的一个或多个值
     // - 提供的文档应该与当前文档属于同一类型，否则不会添加任何内容
     // - 对于对象，使用 dvoCheckForDuplicatedNames 标志：使用 AddOrUpdateFrom() 强制对象合并
    procedure AddFrom(const aDocVariant: Variant);
    /// merge (i.e. add or update) several values from another object
    // - current document should be an object
    /// 合并（即添加或更新）另一个对象的多个值
     // - 当前文档应该是一个对象
    procedure AddOrUpdateFrom(const aDocVariant: Variant;
      aOnlyAddMissing: boolean = false);
    /// add one or several properties, specified by path, from another object
    // - path are defined as open array, e.g. ['doc','glossary','title'], but
    // could also contained nested paths, e.g. ['doc.glossary', title'] or
    // ['doc', 'glossary/title'] of aPathDelim is '/'
    // - matching values would be added as root values, with the path as name
    // - instance and supplied aSource should be a dvObject
    /// 从另一个对象添加一个或多个由路径指定的属性
     // - 路径被定义为开放数组，例如 ['doc','glossary','title']，但也可以包含嵌套路径，例如 aPathDelim 的 ['doc.glossary', title'] 或 ['doc', 'glossary/title'] 是 '/'
     // - 匹配值将作为根值添加，路径作为名称
     // - 实例和提供的 aSource 应该是 dvObject
    procedure AddByPath(const aSource: TDocVariantData;
      const aPaths: array of RawUtf8; aPathDelim: AnsiChar = '.');
    /// delete a value/item in this document, from its index
    // - return TRUE on success, FALSE if the supplied index is not correct
    /// 从文档的索引中删除一个值/项目
     // - 成功时返回 TRUE，如果提供的索引不正确则返回 FALSE
    function Delete(Index: PtrInt): boolean; overload;
    /// delete a value/item in this document, from its name
    // - return TRUE on success, FALSE if the supplied name does not exist
    /// 从文档的名称中删除一个值/项目
     // - 成功时返回 TRUE，如果提供的名称不存在则返回 FALSE
    function Delete(const aName: RawUtf8): boolean; overload;
    /// delete/filter some values/items in this document, from their name
    // - return the number of deleted items
    /// 从名称中删除/过滤本文档中的某些值/项目
     // - 返回已删除项目的数量
    function Delete(const aNames: array of RawUtf8): integer; overload;
    /// delete a value/item in this document, from its name
    // - path is defined as a dotted name-space, e.g. 'doc.glossary.title'
    // - return TRUE on success, FALSE if the supplied name does not exist
    // - you can set e.g. aPathDelim = '/' to search e.g. for 'parent/child'
    /// 从文档的名称中删除一个值/项目
     // - 路径被定义为点状命名空间，例如 '文档.词汇表.标题'
     // - 成功时返回 TRUE，如果提供的名称不存在则返回 FALSE
     // - 你可以设置例如 aPathDelim = '/' 进行搜索，例如 对于“父母/孩子”
    function DeleteByPath(const aPath: RawUtf8; aPathDelim: AnsiChar = '.'): boolean;
    /// delete a value in this document, by property name match
    // - {aPropName:aPropValue} will be searched within the stored array or
    // object, and the corresponding item will be deleted, on match
    // - returns FALSE if no match is found, TRUE if found and deleted
    // - will call VariantEquals() for value comparison
    /// 删除本文档中的一个值，通过属性名匹配
     // - {aPropName:aPropValue} 将在存储的数组或对象中搜索，匹配时相应的项目将被删除
     // - 如果未找到匹配则返回 FALSE，如果找到并删除则返回 TRUE
     // - 将调用 VariantEquals() 进行值比较
    function DeleteByProp(const aPropName, aPropValue: RawUtf8;
      aPropValueCaseSensitive: boolean): boolean;
    /// delete one or several value/item in this document, from its value
    // - returns the number of deleted items
    // - returns 0 if the document is not a dvObject, or if no match was found
    // - if the value exists several times, all occurences would be removed
    // - is optimized for DeleteByValue(null) call
    /// 从其值中删除此文档中的一个或多个值/项
     // - 返回已删除项目的数量
     // - 如果文档不是 dvObject，或者没有找到匹配项，则返回 0
     // - 如果该值存在多次，则所有出现的情况都将被删除
     // - 针对DeleteByValue(null) 调用进行了优化
    function DeleteByValue(const aValue: Variant;
      CaseInsensitive: boolean = false): integer;
    /// delete all values matching the first characters of a property name
    // - returns the number of deleted items
    // - returns 0 if the document is not a dvObject, or if no match was found
    // - will use IdemPChar(), so search would be case-insensitive
    /// 删除与属性名称的第一个字符匹配的所有值
     // - 返回已删除项目的数量
     // - 如果文档不是 dvObject，或者没有找到匹配项，则返回 0
     // - 将使用 IdemPChar()，因此搜索不区分大小写
    function DeleteByStartName(aStartName: PUtf8Char;
      aStartNameLen: integer): integer;
    /// search a property match in this document, handled as array or object
    // - {aPropName:aPropValue} will be searched within the stored array or
    // object, and the corresponding item index will be returned, on match
    // - returns -1 if no match is found
    // - will call VariantEquals() for value comparison
    /// 在此文档中搜索属性匹配，作为数组或对象处理
     // - {aPropName:aPropValue} 将在存储的数组或对象中搜索，匹配时将返回相应的项目索引
     // - 如果没有找到匹配则返回-1
     // - 将调用 VariantEquals() 进行值比较
    function SearchItemByProp(const aPropName, aPropValue: RawUtf8;
      aPropValueCaseSensitive: boolean): integer; overload;
    /// search a property match in this document, handled as array or object
    // - {aPropName:aPropValue} will be searched within the stored array or
    // object, and the corresponding item index will be returned, on match
    // - returns -1 if no match is found
    // - will call VariantEquals() for value comparison
    /// 在此文档中搜索属性匹配，作为数组或对象处理
     // - {aPropName:aPropValue} 将在存储的数组或对象中搜索，匹配时将返回相应的项目索引
     // - 如果没有找到匹配则返回-1
     // - 将调用 VariantEquals() 进行值比较
    function SearchItemByProp(const aPropNameFmt: RawUtf8;
      const aPropNameArgs: array of const; const aPropValue: RawUtf8;
      aPropValueCaseSensitive: boolean): integer; overload;
    /// search a value in this document, handled as array
    // - aValue will be searched within the stored array
    // and the corresponding item index will be returned, on match
    // - returns -1 if no match is found
    // - you could make several searches, using the StartIndex optional parameter
    /// 在此文档中搜索一个值，作为数组处理
     // - aValue 将在存储的数组中搜索，匹配时将返回相应的项目索引
     // - 如果没有找到匹配则返回-1
     // - 您可以使用 StartIndex 可选参数进行多次搜索
    function SearchItemByValue(const aValue: Variant;
      CaseInsensitive: boolean = false; StartIndex: PtrInt = 0): PtrInt;
    /// sort the document object values by name
    // - do nothing if the document is not a dvObject
    // - will follow case-insensitive order (@StrIComp) by default, but you
    // can specify @StrComp as comparer function for case-sensitive ordering
    // - once sorted, you can use GetVarData(..,Compare) or GetAs*(..,Compare)
    // methods for much faster O(log(n)) binary search
    /// 按名称对文档对象值进行排序
     // - 如果文档不是 dvObject，则不执行任何操作
     // - 默认情况下将遵循不区分大小写的顺序（@StrIComp），但是您
     // 可以指定@StrComp作为区分大小写排序的比较器函数
     // - 一旦排序，您可以使用 GetVarData(..,Compare) 或 GetAs*(..,Compare) 方法来实现更快的 O(log(n)) 二分搜索
    procedure SortByName(SortCompare: TUtf8Compare = nil;
      SortCompareReversed: boolean = false);
    /// sort the document object values by value using a comparison function
    // - work for both dvObject and dvArray documents
    // - will sort by UTF-8 text (VariantCompare) if no custom aCompare is supplied
    /// 使用比较函数按值对文档对象值进行排序
     // - 适用于 dvObject 和 dvArray 文档
     // - 如果未提供自定义 aCompare，将按 UTF-8 文本 (VariantCompare) 排序
    procedure SortByValue(SortCompare: TVariantCompare = nil;
      SortCompareReversed: boolean = false);
    /// sort the document object values by value using a comparison method
    // - work for both dvObject and dvArray documents
    // - you should supply a TVariantComparer callback method
    /// 使用比较方法按值对文档对象值进行排序
     // - 适用于 dvObject 和 dvArray 文档
     // - 您应该提供 TVariantComparer 回调方法
    procedure SortByRow(const SortComparer: TVariantComparer;
      SortComparerReversed: boolean = false);
    /// sort the document array values by a field of some stored objet values
    // - do nothing if the document is not a dvArray, or if the items are no dvObject
    // - aValueCompare will be called with the aItemPropName values, not row
    // - will sort by UTF-8 text (VariantCompare) if no custom aValueCompare is supplied
    // - this method is faster than SortByValue/SortByRow
    /// 按某些存储对象值的字段对文档数组值进行排序
     // - 如果文档不是 dvArray，或者项目不是 dvObject，则不执行任何操作
     // - aValueCompare 将使用 aItemPropName 值（而不是行）调用
     // - 如果未提供自定义 aValueCompare，将按 UTF-8 文本 (VariantCompare) 排序
     // - 此方法比 SortByValue/SortByRow 更快
    procedure SortArrayByField(const aItemPropName: RawUtf8;
      aValueCompare: TVariantCompare = nil;
      aValueCompareReverse: boolean = false;
      aNameSortedCompare: TUtf8Compare = nil);
    /// sort the document array values by field(s) of some stored objet values
    // - allow up to 4 fields (aItemPropNames[0]..aItemPropNames[3])
    // - do nothing if the document is not a dvArray, or if the items are no dvObject
    // - will sort by UTF-8 text (VariantCompare) if no aValueCompareField is supplied
    /// 按某些存储对象值的字段对文档数组值进行排序
     // - 最多允许 4 个字段 (aItemPropNames[0]..aItemPropNames[3])
     // - 如果文档不是 dvArray，或者项目不是 dvObject，则不执行任何操作
     // - 如果未提供 aValueCompareField，将按 UTF-8 文本
    procedure SortArrayByFields(const aItemPropNames: array of RawUtf8;
      aValueCompare: TVariantCompare = nil;
      const aValueCompareField: TVariantCompareField = nil;
      aValueCompareReverse: boolean = false; aNameSortedCompare: TUtf8Compare = nil);
    /// inverse the order of Names and Values of this document
    // - could be applied after a content sort if needed
    /// 反转本文档的名称和值的顺序
     // - 如果需要，可以在内容排序之后应用
    procedure Reverse;
    /// create a TDocVariant object, from a selection of properties of the
    // objects of this document array, by property name
    // - if the document is a dvObject, to reduction will be applied to all
    // its properties
    // - if the document is a dvArray, the reduction will be applied to each
    // stored item, if it is a document
    /// 根据属性名称从该文档数组的对象属性中创建一个 TDocVariant 对象
     // - 如果文档是 dvObject，则归约将应用于其所有属性
     // - 如果文档是 dvArray，则缩减将应用于每个存储的项目（如果它是文档）
    procedure Reduce(const aPropNames: array of RawUtf8; aCaseSensitive: boolean;
      var result: TDocVariantData; aDoNotAddVoidProp: boolean = false); overload;
    /// create a TDocVariant object, from a selection of properties of the
    // objects of this document array, by property name
    // - always returns a TDocVariantData, even if no property name did match
    // (in this case, it is dvUndefined)
    /// 根据属性名称从该文档数组的对象属性中创建一个 TDocVariant 对象
     // - 始终返回 TDocVariantData，即使没有匹配的属性名称（在本例中为 dvUndefined）
    function Reduce(const aPropNames: array of RawUtf8; aCaseSensitive: boolean;
      aDoNotAddVoidProp: boolean = false): variant; overload;
    /// create a TDocVariant array, from the values of a single property of the
    // objects of this document array, specified by name
    // - you can optionally apply an additional filter to each reduced item
    /// 根据此文档数组的对象的单个属性的值创建一个 TDocVariant 数组，按名称指定
     // - 您可以选择对每个减少的项目应用额外的过滤器
    procedure ReduceAsArray(const aPropName: RawUtf8;
      var result: TDocVariantData;
      const OnReduce: TOnReducePerItem = nil); overload;
    /// create a TDocVariant array, from the values of a single property of the
    // objects of this document array, specified by name
    // - always returns a TDocVariantData, even if no property name did match
    // (in this case, it is dvUndefined)
    // - you can optionally apply an additional filter to each reduced item
    /// 根据此文档数组的对象的单个属性的值创建一个 TDocVariant 数组，按名称指定
     // - 始终返回 TDocVariantData，即使没有匹配的属性名称（在本例中为 dvUndefined）
     // - 您可以选择对每个减少的项目应用额外的过滤器
    function ReduceAsArray(const aPropName: RawUtf8;
      const OnReduce: TOnReducePerItem = nil): variant; overload;
    /// create a TDocVariant array, from the values of a single property of the
    // objects of this document array, specified by name
    // - this overloaded method accepts an additional filter to each reduced item
    /// 根据此文档数组的对象的单个属性的值创建一个 TDocVariant 数组，按名称指定
     // - 此重载方法接受每个缩减项的附加过滤器
    procedure ReduceAsArray(const aPropName: RawUtf8;
      var result: TDocVariantData;
      const OnReduce: TOnReducePerValue); overload;
    /// create a TDocVariant array, from the values of a single property of the
    // objects of this document array, specified by name
    // - always returns a TDocVariantData, even if no property name did match
    // (in this case, it is dvUndefined)
    // - this overloaded method accepts an additional filter to each reduced item
    /// 根据此文档数组的对象的单个属性的值创建一个 TDocVariant 数组，按名称指定
     // - 始终返回 TDocVariantData，即使没有匹配的属性名称（在本例中为 dvUndefined）
     // - 此重载方法接受每个缩减项的附加过滤器
    function ReduceAsArray(const aPropName: RawUtf8;
      const OnReduce: TOnReducePerValue): variant; overload;
    /// return the variant values of a single property of the objects of this
    // document array, specified by name
    // - returns nil if the document is not a dvArray
    /// 返回此文档数组的对象的单个属性的变体值，由名称指定
     // - 如果文档不是 dvArray，则返回 nil
    function ReduceAsVariantArray(const aPropName: RawUtf8;
      aDuplicates: TSearchDuplicate = sdNone): TVariantDynArray;
    /// rename some properties of a TDocVariant object
    // - returns the number of property names modified
    /// 重命名 TDocVariant 对象的一些属性
     // - 返回修改的属性名称的数量
    function Rename(const aFromPropName, aToPropName: TRawUtf8DynArray): integer;
    /// return a dynamic array with all dvObject Names, and length() = Count
    // - since length(Names) = Capacity, you can use this method to retrieve
    // all the object keys
    // - consider using FieldNames iterator or Names[0..Count-1] if you need
    // to iterate on the key names
    // - will internally force length(Names)=length(Values)=Capacity=Count and
    // return the Names[] instance with no memory (re)allocation
    // - if the document is not a dvObject, will return nil
    /// 返回包含所有 dvObject 名称的动态数组，且 length() = Count
     // - 由于 length(Names) = Capacity，您可以使用此方法检索所有对象键
     // - 如果需要迭代键名称，请考虑使用 FieldNames 迭代器或 Names[0..Count-1]
     // - 将在内部强制 length(Names)=length(Values)=Capacity=Count 并返回 Names[] 实例，无需内存（重新）分配
     // - 如果文档不是 dvObject，将返回 nil
    function GetNames: TRawUtf8DynArray;
    /// map {"obj.prop1"..,"obj.prop2":..} into {"obj":{"prop1":..,"prop2":...}}
    // - the supplied aObjectPropName should match the incoming dotted value
    // of all properties (e.g. 'obj' for "obj.prop1")
    // - if any of the incoming property is not of "obj.prop#" form, the
    // whole process would be ignored
    // - return FALSE if the TDocVariant did not change
    // - return TRUE if the TDocVariant has been flattened
    /// 将 {"obj.prop1"..,"obj.prop2":..} 映射到 {"obj":{"prop1":..,"prop2":...}}
     // - 提供的 aObjectPropName 应与所有属性的传入点值匹配（例如“obj”代表“obj.prop1”）
     // - 如果任何传入属性不是“obj.prop#”形式，则整个过程将被忽略
     // - 如果 TDocVariant 未更改，则返回 FALSE
     // - 如果 TDocVariant 已被展平，则返回 TRUE
    function FlattenAsNestedObject(const aObjectPropName: RawUtf8): boolean;

    /// how this document will behave
    // - those options are set when creating the instance
    // - dvoArray and dvoObject are not options, but define the document Kind,
    // so those items are ignored when assigned to this property
    /// 该文档的行为方式
     // - 这些选项在创建实例时设置
     // - dvoArray 和 dvoObject 不是选项，而是定义文档 Kind，因此在分配给此属性时这些项目将被忽略
    property Options: TDocVariantOptions
      read VOptions write SetOptions;
    /// returns the document internal layout
    // - just after initialization, it will return dvUndefined
    // - most of the time, you will add named values with AddValue() or by
    // setting the variant properties: it will return dvObject
    // - but is you use AddItem(), values will have no associated names: the
    // document will be a dvArray
    // - value computed from the dvoArray and dvoObject presence in Options
    /// 返回文档内部布局
     // - 初始化后，它将返回 dvUndefined
     // - 大多数时候，您将使用 AddValue() 或通过设置变体属性来添加命名值：它将返回 dvObject
     // - 但是如果您使用 AddItem()，值将没有关联的名称：文档将是 dvArray
     // - 根据选项中存在的 dvoArray 和 dvoObject 计算得出的值
    property Kind: TDocVariantKind
      read GetKind;
    /// return the custom variant type identifier, i.e. DocVariantType.VarType
    /// 返回自定义变体类型标识符，即 DocVariantType.VarType
    property VarType: word
      read VType;
    /// number of items stored in this document
    // - is 0 if Kind=dvUndefined
    // - is the number of name/value pairs for Kind=dvObject
    // - is the number of items for Kind=dvArray
    /// 该文档中存储的项目数
     // - 如果 Kind=dvUndefined 则为 0
     // - 是 Kind=dvObject 的名称/值对的数量
     // - 是 Kind=dvArray 的项目数
    property Count: integer
      read VCount;
    /// the current capacity of this document
    // - allow direct access to VValue[] length
    /// 该文件的当前容量
     // - 允许直接访问 VValue[] 长度
    property Capacity: integer
      read GetCapacity write SetCapacity;
    /// direct acces to the low-level internal array of values
    // - note that length(Values)=Capacity and not Count, so copy(Values, 0, Count)
    // or use FieldValues iterator if you want the exact count
    // - transtyping a variant and direct access to TDocVariantData is the
    // fastest way of accessing all properties of a given dvObject:
    // ! with _Safe(aVariantObject)^ do
    // !   for i := 0 to Count-1 do
    // !     writeln(Names[i],'=',Values[i]);
    // - or to access a dvArray items (e.g. a MongoDB collection):
    // ! with TDocVariantData(aVariantArray) do
    // !   for i := 0 to Count-1 do
    // !     writeln(Values[i]);
    /// 直接访问低级内部值数组
     // - 请注意 length(Values)=Capacity 而不是 Count，因此如果您想要精确的计数，请复制(Values, 0, Count) 或使用 FieldValues 迭代器
     // - 转换变体并直接访问 TDocVariantData 是访问给定 dvObject 所有属性的最快方法：
    // ! with _Safe(aVariantObject)^ do
    // !   for i := 0 to Count-1 do
    // !     writeln(Names[i],'=',Values[i]);
    // - or to access a dvArray items (e.g. a MongoDB collection):
    // ! with TDocVariantData(aVariantArray) do
    // !   for i := 0 to Count-1 do
    // !     writeln(Values[i]);
    property Values: TVariantDynArray
      read VValue;
    /// direct acces to the low-level internal array of names
    // - is void (nil) if Kind is not dvObject
    // - note that length(Names)=Capacity and not Count, so copy(Names, 0, Count)
    // or use FieldNames iterator or GetNames if you want the exact count
    // - transtyping a variant and direct access to TDocVariantData is the
    // fastest way of accessing all properties of a given dvObject:
    // ! with _Safe(aVariantObject)^ do
    // !   for i := 0 to Count-1 do
    // !     writeln(Names[i],'=',Values[i]);
    /// 直接访问低级内部名称数组
     // - 如果 Kind 不是 dvObject，则为 void (nil)
     // - 请注意 length(Names)=Capacity 而不是 Count，因此如果需要精确的计数，请复制(Names, 0, Count) 或使用 FieldNames 迭代器或 GetNames
     // - 转换变体并直接访问 TDocVariantData 是访问给定 dvObject 所有属性的最快方法：
    // ! with _Safe(aVariantObject)^ do
    // !   for i := 0 to Count-1 do
    // !     writeln(Names[i],'=',Values[i]);
    property Names: TRawUtf8DynArray
      read VName;
    /// find an item in this document, and returns its value
    // - raise an EDocVariant if aNameOrIndex is neither an integer nor a string
    // - raise an EDocVariant if Kind is dvArray and aNameOrIndex is a string
    // or if Kind is dvObject and aNameOrIndex is an integer
    // - raise an EDocVariant if Kind is dvObject and if aNameOrIndex is a
    // string, which is not found within the object property names and
    // dvoReturnNullForUnknownProperty is set in Options
    // - raise an EDocVariant if Kind is dvArray and if aNameOrIndex is a
    // integer, which is not within 0..Count-1 and dvoReturnNullForUnknownProperty
    // is set in Options
    // - so you can use directly:
    // ! // for an array document:
    // ! aVariant := TDocVariant.NewArray(['one',2,3.0]);
    // ! for i := 0 to TDocVariantData(aVariant).Count-1 do
    // !   aValue := TDocVariantData(aVariant).Value[i];
    // ! // for an object document:
    // ! aVariant := TDocVariant.NewObject(['name','John','year',1972]);
    // ! assert(aVariant.Name=TDocVariantData(aVariant)['name']);
    // ! assert(aVariant.year=TDocVariantData(aVariant)['year']);
    // - due to the internal implementation of variant execution (somewhat
    // slow _DispInvoke() function), it is a bit faster to execute:
    // ! aValue := TDocVariantData(aVariant).Value['name'];
    // or
    // ! aValue := _Safe(aVariant).Value['name'];
    // instead of
    // ! aValue := aVariant.name;
    // but of course, if want to want to access the content by index (typically
    // for a dvArray), using Values[] - and Names[] - properties is much faster
    // than this variant-indexed pseudo-property:
    // ! with TDocVariantData(aVariant) do
    // !   for i := 0 to Count-1 do
    // !     Writeln(Values[i]);
    // is faster than:
    // ! with TDocVariantData(aVariant) do
    // !   for i := 0 to Count-1 do
    // !     Writeln(Value[i]);
    // which is faster than:
    // ! for i := 0 to aVariant.Count-1 do
    // !   Writeln(aVariant._(i));
    // - this property will return the value as varByRef (just like with
    // variant late binding of any TDocVariant instance), so you can write:
    // !var
    // !  Doc: TDocVariantData; // stack-allocated variable
    // !begin
    // !  Doc.InitJson('{arr:[1,2]}');
    // !  assert(Doc.Count=2);
    // !  Doc.Value['arr'].Add(3);  // works since Doc.Value['arr'] is varByRef
    // !  writeln(Doc.ToJson);      // will write '{"arr":[1,2,3]}'
    // !end;
    // - if you want to access a property as a copy, i.e. to assign it to a
    // variant variable which will stay alive after this TDocVariant instance
    // is release, you should not use Value[] but rather
    // GetValueOrRaiseException or GetValueOrNull/GetValueOrEmpty
    // - see U[] I[] B[] D[] O[] O_[] A[] A_[] _[] properties for direct access
    // of strong typed values, or P[] to retrieve a variant from its path
    /// 在这个文档中查找一个项目，并返回它的值
     // - 如果 aNameOrIndex 既不是整数也不是字符串，则引发 EDocVariant
     // - 如果 Kind 是 dvArray 并且 aNameOrIndex 是字符串，或者 Kind 是 dvObject 并且 aNameOrIndex 是整数，则引发 EDocVariant
     // - 如果 Kind 是 dvObject 并且 aNameOrIndex 是字符串（在对象属性名称中找不到该字符串）并且在选项中设置了 dvoReturnNullForUnknownProperty，则引发 EDocVariant
     // - 如果 Kind 是 dvArray 并且 aNameOrIndex 是不在 0..Count-1 范围内的整数并且在选项中设置了 dvoReturnNullForUnknownProperty，则引发 EDocVariant
     // - 所以你可以直接使用：
    // ! // for an array document:
    // ! aVariant := TDocVariant.NewArray(['one',2,3.0]);
    // ! for i := 0 to TDocVariantData(aVariant).Count-1 do
    // !   aValue := TDocVariantData(aVariant).Value[i];
    // ! // for an object document:
    // ! aVariant := TDocVariant.NewObject(['name','John','year',1972]);
    // ! assert(aVariant.Name=TDocVariantData(aVariant)['name']);
    // ! assert(aVariant.year=TDocVariantData(aVariant)['year']);
     // - 由于变体执行的内部实现（_DispInvoke() 函数有点慢），执行起来有点快：
     // ! aValue := TDocVariantData(aVariant).Value['name'];
     // 或者
     // ! aValue := _Safe(aVariant).Value['name'];
     // 代替
     // ! aValue := aVariant.name;
     // 但是当然，如果想通过索引访问内容（通常对于 dvArray），使用 Values[] - 和 Names[] - 属性比这个变体索引伪属性要快得多：
    // ! with TDocVariantData(aVariant) do
    // !   for i := 0 to Count-1 do
    // !     Writeln(Values[i]);
     // 比以下更快
    // ! with TDocVariantData(aVariant) do
    // !   for i := 0 to Count-1 do
    // !     Writeln(Value[i]);
     // 这比以下更快：
    // ! for i := 0 to aVariant.Count-1 do
    // !   Writeln(aVariant._(i));
     // - 此属性将以 varByRef 形式返回值（就像任何 TDocVariant 实例的变体后期绑定一样），因此您可以编写：
    // !var
    // !  Doc: TDocVariantData; // stack-allocated variable
    // !begin
    // !  Doc.InitJson('{arr:[1,2]}');
    // !  assert(Doc.Count=2);
    // !  Doc.Value['arr'].Add(3);  // works since Doc.Value['arr'] is varByRef
    // !  writeln(Doc.ToJson);      // will write '{"arr":[1,2,3]}'
    // !end;
     // - 如果您想以副本形式访问属性，即将其分配给一个变体变量，该变体变量在此 TDocVariant 实例释放后仍保持活动状态，则不应使用 Value[]，而应使用 GetValueOrRaiseException 或 GetValueOrNull/GetValueOrEmpty
     // - 请参阅 U[] I[] B[] D[] O[] O_[] A[] A_[] _[] 属性以直接访问强类型值，或使用 P[] 从其检索变体 小路    
    property Value[const aNameOrIndex: Variant]: Variant
      read GetValueOrItem write SetValueOrItem; default;

    /// direct access to a dvObject UTF-8 stored property value from its name
    // - slightly faster than the variant-based Value[] default property
    // - follows dvoNameCaseSensitive and dvoReturnNullForUnknownProperty options
    // - use GetAsRawUtf8() if you want to check the availability of the field
    // - U['prop'] := 'value' would add a new property, or overwrite an existing
    /// 从dvObject的名称直接访问UTF-8存储的属性值
     // - 比基于变体的 Value[] 默认属性稍快
     // - 遵循 dvoNameCaseSensitive 和 dvoReturnNullForUnknownProperty 选项
     // - 如果您想检查字段的可用性，请使用 GetAsRawUtf8()
     // - U['prop'] := 'value' 将添加新属性，或覆盖现有属性
    property U[const aName: RawUtf8]: RawUtf8
      read GetRawUtf8ByName write SetRawUtf8ByName;
    /// direct string access to a dvObject UTF-8 stored property value from its name
    // - just a wrapper around U[] property, to avoid a compilation warning when
    // using plain string variables (internally, RawUtf8 will be used for storage)
    // - slightly faster than the variant-based Value[] default property
    // - follows dvoNameCaseSensitive and dvoReturnNullForUnknownProperty options
    // - use GetAsRawUtf8() if you want to check the availability of the field
    // - S['prop'] := 'value' would add a new property, or overwrite an existing
    /// 从名称直接字符串访问 dvObject UTF-8 存储的属性值
     // - 只是 U[] 属性的包装，以避免使用纯字符串变量时出现编译警告（内部将使用 RawUtf8 进行存储）
     // - 比基于变体的 Value[] 默认属性稍快
     // - 遵循 dvoNameCaseSensitive 和 dvoReturnNullForUnknownProperty 选项
     // - 如果您想检查字段的可用性，请使用 GetAsRawUtf8()
     // - S['prop'] := 'value' 将添加新属性，或覆盖现有属性
    property S[const aName: RawUtf8]: string
      read GetStringByName write SetStringByName;
    /// direct access to a dvObject integer stored property value from its name
    // - slightly faster than the variant-based Value[] default property
    // - follows dvoNameCaseSensitive and dvoReturnNullForUnknownProperty options
    // - use GetAsInt/GetAsInt64 if you want to check the availability of the field
    // - I['prop'] := 123 would add a new property, or overwrite an existing
    /// 从其名称直接访问 dvObject 整数存储的属性值
     // - 比基于变体的 Value[] 默认属性稍快
     // - 遵循 dvoNameCaseSensitive 和 dvoReturnNullForUnknownProperty 选项
     // - 如果您想检查字段的可用性，请使用 GetAsInt/GetAsInt64
     // - I['prop'] := 123 将添加新属性，或覆盖现有属性
    property I[const aName: RawUtf8]: Int64
      read GetInt64ByName write SetInt64ByName;
    /// direct access to a dvObject boolean stored property value from its name
    // - slightly faster than the variant-based Value[] default property
    // - follows dvoNameCaseSensitive and dvoReturnNullForUnknownProperty options
    // - use GetAsBoolean if you want to check the availability of the field
    // - B['prop'] := true would add a new property, or overwrite an existing
    /// 从名称直接访问 dvObject 布尔存储属性值
     // - 比基于变体的 Value[] 默认属性稍快
     // - 遵循 dvoNameCaseSensitive 和 dvoReturnNullForUnknownProperty 选项
     // - 如果您想检查字段的可用性，请使用 GetAsBoolean
     // - B['prop'] := true 将添加新属性，或覆盖现有属性
    property B[const aName: RawUtf8]: boolean
      read GetBooleanByName write SetBooleanByName;
    /// direct access to a dvObject floating-point stored property value from its name
    // - slightly faster than the variant-based Value[] default property
    // - follows dvoNameCaseSensitive and dvoReturnNullForUnknownProperty options
    // - use GetAsDouble if you want to check the availability of the field
    // - D['prop'] := 1.23 would add a new property, or overwrite an existing
    /// 从dvObject的名称直接访问浮点存储的属性值
     // - 比基于变体的 Value[] 默认属性稍快
     // - 遵循 dvoNameCaseSensitive 和 dvoReturnNullForUnknownProperty 选项
     // - 如果您想检查字段的可用性，请使用 GetAsDouble
     // - D['prop'] := 1.23 将添加新属性，或覆盖现有属性
    property D[const aName: RawUtf8]: Double
      read GetDoubleByName write SetDoubleByName;
    /// direct access to a dvObject existing dvObject property from its name
    // - follows dvoNameCaseSensitive and dvoReturnNullForUnknownProperty options
    // - O['prop'] would return a fake void TDocVariant if the property is not
    // existing or not a dvObject, just like GetAsDocVariantSafe()
    // - use O_['prop'] to force adding any missing property
    /// 从dvObject的名称直接访问现有的dvObject属性
     // - 遵循 dvoNameCaseSensitive 和 dvoReturnNullForUnknownProperty 选项
     // - 如果属性不存在或不是 dvObject，O['prop'] 将返回一个假 void TDocVariant，就像 GetAsDocVariantSafe() 一样
     // - 使用 O_['prop'] 强制添加任何缺失的属性
    property O[const aName: RawUtf8]: PDocVariantData
      read GetObjectExistingByName;
    /// direct access or add a dvObject's dvObject property from its name
    // - follows dvoNameCaseSensitive and dvoReturnNullForUnknownProperty options
    // - O_['prop'] would add a new property if there is none existing, or
    // overwrite an existing property which is not a dvObject
    // - the new property object would inherit from the Options of this instance
    /// 直接访问或从名称添加dvObject的dvObject属性
     // - 遵循 dvoNameCaseSensitive 和 dvoReturnNullForUnknownProperty 选项
     // - 如果不存在，O_['prop'] 将添加一个新属性，或者覆盖不是 dvObject 的现有属性
     // - 新的属性对象将从该实例的选项继承
    property O_[const aName: RawUtf8]: PDocVariantData
      read GetObjectOrAddByName;
    /// direct access to a dvObject existing dvArray property from its name
    // - follows dvoNameCaseSensitive and dvoReturnNullForUnknownProperty options
    // - A['prop'] would return a fake void TDocVariant if the property is not
    // existing or not a dvArray, just like GetAsDocVariantSafe()
    // - use A_['prop'] to force adding any missing property
    /// 从dvObject的名称直接访问现有的dvArray属性
     // - 遵循 dvoNameCaseSensitive 和 dvoReturnNullForUnknownProperty 选项
     // - 如果属性不存在或不是 dvArray，A['prop'] 将返回一个假 void TDocVariant，就像 GetAsDocVariantSafe() 一样
     // - 使用 A_['prop'] 强制添加任何缺失的属性
    property A[const aName: RawUtf8]: PDocVariantData
      read GetArrayExistingByName;
    /// direct access or add a dvObject's dvArray property from its name
    // - follows dvoNameCaseSensitive and dvoReturnNullForUnknownProperty options
    // - A_['prop'] would add a new property if there is none existing, or
    // overwrite an existing property which is not a dvArray
    // - the new property array would inherit from the Options of this instance
    /// 直接访问或从名称添加 dvObject 的 dvArray 属性
     // - 遵循 dvoNameCaseSensitive 和 dvoReturnNullForUnknownProperty 选项
     // - 如果不存在，A_['prop'] 将添加一个新属性，或者覆盖不是 dvArray 的现有属性
     // - 新的属性数组将从该实例的选项继承
    property A_[const aName: RawUtf8]: PDocVariantData
      read GetArrayOrAddByName;
    /// direct access to a dvArray's TDocVariant property from its index
    // - simple values may directly use Values[] dynamic array, but to access
    // a TDocVariantData members, this property is safer
    // - follows dvoReturnNullForUnknownProperty option to raise an exception
    // - _[ndx] would return a fake void TDocVariant if aIndex is out of range,
    // if the property is not existing or not a TDocVariantData (just like
    // GetAsDocVariantSafe)
    /// 从索引直接访问 dvArray 的 TDocVariant 属性
     // - 简单值可以直接使用Values[]动态数组，但是要访问TDocVariantData成员，这个属性更安全
     // - 遵循 dvoReturnNullForUnknownProperty 选项引发异常
     // - 如果 aIndex 超出范围、属性不存在或不是 TDocVariantData，_[ndx] 将返回假 void TDocVariant（就像 GetAsDocVariantSafe）
    property _[aIndex: integer]: PDocVariantData
      read GetAsDocVariantByIndex;
    /// direct access to a dvObject value stored property value from its path name
    // - default Value[] will check only names in the current object properties,
    // whereas this property will recognize e.g. 'parent.child' nested objects
    // - follows dvoNameCaseSensitive and dvoReturnNullForUnknownProperty options
    /// 从其路径名直接访问dvObject值存储的属性值
     // - 默认 Value[] 将仅检查当前对象属性中的名称，而此属性将识别例如 “parent.child”嵌套对象
     // - 遵循 dvoNameCaseSensitive 和 dvoReturnNullForUnknownProperty 选项
    property P[const aNameOrPath: RawUtf8]: Variant
      read GetVariantByPath;
  end;
  {$A+} { packet object not allowed since Delphi 2009 :( }
  { 自 Delphi 2009 起不允许使用数据包对象:( }

var
  /// the internal custom variant type used to register TDocVariant
  /// 用于注册TDocVariant的内部自定义变体类型
  DocVariantType: TDocVariant;

  /// copy of DocVariantType.VarType
  // - as used by inlined functions of TDocVariantData
  /// DocVariantType.VarType 的副本
   // - 由 TDocVariantData 的内联函数使用
  DocVariantVType: cardinal;

  // defined here for inlining - properly filled in initialization section below
  // 此处定义用于内联 - 正确填写下面的初始化部分
  DV_FAST: array[TDocVariantKind] of TVarData;


/// retrieve the text representation of a TDocVairnatKind
/// 检索 TDocVairnatKind 的文本表示
function ToText(kind: TDocVariantKind): PShortString; overload;

/// direct access to a TDocVariantData from a given variant instance
// - return a pointer to the TDocVariantData corresponding to the variant
// instance, which may be of kind varByRef (e.g. when retrieved by late binding)
// - raise an EDocVariant exception if the instance is not a TDocVariant
// - the following direct trans-typing may fail, e.g. for varByRef value:
// ! TDocVariantData(aVarDoc.ArrayProp).Add('new item');
// - so you can write the following:
// ! DocVariantData(aVarDoc.ArrayProp).AddItem('new item');
// - note: due to a local variable lifetime change in Delphi 11, don't use
// this function with a temporary variant (e.g. from TList<variant>.GetItem) -
// call _DV() and a local TDocVariantData instead of a PDocVariantData
/// 从给定的变体实例直接访问 TDocVariantData
// - 返回指向对应于变体实例的 TDocVariantData 的指针，该指针可能是 varByRef 类型（例如，当通过后期绑定检索时）
// - 如果实例不是 TDocVariant，则引发 EDocVariant 异常
// - 以下直接转输入可能会失败，例如 对于 varByRef 值：
//！ TDocVariantData(aVarDoc.ArrayProp).Add('新项目');
// - 所以你可以编写以下内容：
//！ DocVariantData(aVarDoc.ArrayProp).AddItem('新项目');
// - 注意：由于 Delphi 11 中的局部变量生命周期发生变化，请勿将此函数与临时变量一起使用（例如，来自 TList<variant>.GetItem） - 调用 _DV() 和本地 TDocVariantData 而不是 PDocVariantData
function DocVariantData(const DocVariant: variant): PDocVariantData;

const
  /// constant used e.g. by _Safe() and _DV() overloaded functions
  // - will be in code section of the exe, so will be read-only by design
  // - would have Kind=dvUndefined and Count=0, so _Safe() would return
  // a valid, but void document
  // - its VType is varNull, so would be viewed as a null variant
  // - dvoReturnNullForUnknownProperty is defined, so that U[]/I[]... methods
  // won't raise any exception about unexpected field name
  /// 使用常量，例如 通过 _Safe() 和 _DV() 重载函数
   // - 将位于 exe 的代码部分，因此设计为只读
   // - Kind=dvUndefined 且 Count=0，因此 _Safe() 将返回有效但无效的文档
   // - 它的 VType 是 varNull，因此将被视为空变体
   // - 定义了 dvoReturnNullForUnknownProperty，以便 U[]/I[]... 方法不会引发任何有关意外字段名称的异常
  DocVariantDataFake: TDocVariantData = (
    VType: varNull;
    VOptions: [dvoReturnNullForUnknownProperty]{%H-});

/// direct access to a TDocVariantData from a given variant instance
// - return a pointer to the TDocVariantData corresponding to the variant
// instance, which may be of kind varByRef (e.g. when retrieved by late binding)
// - will return a read-only fake TDocVariantData with Kind=dvUndefined if the
// supplied variant is not a TDocVariant instance, so could be safely used
// in a with block (use "with" moderation, of course):
// ! with _Safe(aDocVariant)^ do
// !   for ndx := 0 to Count-1 do // here Count=0 for the "fake" result
// !     writeln(Names[ndx]);
// or excluding the "with" statement, as more readable code:
// ! var dv: PDocVariantData;
// !     ndx: PtrInt;
// ! begin
// !   dv := _Safe(aDocVariant);
// !   for ndx := 0 to dv.Count-1 do // here Count=0 for the "fake" result
// !     writeln(dv.Names[ndx]);
// - note: due to a local variable lifetime change in Delphi 11, don't use
// this function with a temporary variant (e.g. from TList<variant>.GetItem) -
// call _DV() and a local TDocVariantData instead of a PDocVariantData
/// 从给定的变体实例直接访问 TDocVariantData
// - 返回指向对应于变体实例的 TDocVariantData 的指针，该指针可能是 varByRef 类型（例如，当通过后期绑定检索时）
// - 如果提供的变体不是 TDocVariant 实例，将返回一个 Kind=dvUndefined 的只读假 TDocVariantData，因此可以安全地在 with 块中使用（当然，使用“with”审核）：
// ! with _Safe(aDocVariant)^ do
// !   for ndx := 0 to Count-1 do // here Count=0 for the "fake" result
// !     writeln(Names[ndx]);
// 或排除“with”语句，作为更具可读性的代码：
// ! var dv: PDocVariantData;
// !     ndx: PtrInt;
// ! begin
// !   dv := _Safe(aDocVariant);
// !   for ndx := 0 to dv.Count-1 do // here Count=0 for the "fake" result
// !     writeln(dv.Names[ndx]);
// - 注意：由于 Delphi 11 中的局部变量生命周期发生变化，请勿将此函数与临时变量一起使用（例如，来自 TList<variant>.GetItem） - 调用 _DV() 和本地 TDocVariantData 而不是 PDocVariantData
function _Safe(const DocVariant: variant): PDocVariantData; overload;
  {$ifdef FPC}inline;{$endif} // Delphi has problems inlining this :(

/// direct access to a TDocVariantData from a given variant instance
// - return a pointer to the TDocVariantData corresponding to the variant
// instance, which may be of kind varByRef (e.g. when retrieved by late binding)
// - will check the supplied document kind, i.e. either dvObject or dvArray and
// raise a EDocVariant exception if it does not match
// - note: due to a local variable lifetime change in Delphi 11, don't use
// this function with a temporary variant (e.g. from TList<variant>.GetItem) -
// call _DV() and a local TDocVariantData instead of a PDocVariantData
/// 从给定的变体实例直接访问 TDocVariantData
// - 返回指向对应于变体实例的 TDocVariantData 的指针，该指针可能是 varByRef 类型（例如，当通过后期绑定检索时）
// - 将检查提供的文档类型，即 dvObject 或 dvArray，如果不匹配则引发 EDocVariant 异常
// - 注意：由于 Delphi 11 中的局部变量生命周期发生变化，请勿将此函数与临时变量一起使用（例如，来自 TList<variant>.GetItem） - 调用 _DV() 和本地 TDocVariantData 而不是 PDocVariantData
function _Safe(const DocVariant: variant;
  ExpectedKind: TDocVariantKind): PDocVariantData; overload;
  {$ifdef HASINLINE}inline;{$endif}

/// direct access to a TDocVariantData from a given variant instance
// - return true and set DocVariant with a pointer to the TDocVariantData
// corresponding to the variant instance, which may be of kind varByRef
// (e.g. when retrieved by late binding)
// - return false if the supplied Value is not a TDocVariant, but e.g. a string,
// a number or another type of custom variant
// - note: due to a local variable lifetime change in Delphi 11, don't use
// this function with a temporary variant (e.g. from TList<variant>.GetItem) -
// call _DV() and a local TDocVariantData instead of a PDocVariantData
/// 从给定的变体实例直接访问 TDocVariantData
// - 返回 true 并使用指向对应于变体实例的 TDocVariantData 的指针设置 DocVariant，该指针可能是 varByRef 类型（例如，当通过后期绑定检索时）
// - 如果提供的 Value 不是 TDocVariant，而是例如，则返回 false 字符串、数字或其他类型的自定义变体
// - 注意：由于 Delphi 11 中的局部变量生命周期发生变化，请勿将此函数与临时变量一起使用（例如，来自 TList<variant>.GetItem） - 调用 _DV() 和本地 TDocVariantData 而不是 PDocVariantData
function _Safe(const DocVariant: variant; out DV: PDocVariantData): boolean; overload;
  {$ifdef HASINLINE}inline;{$endif}

/// direct access to a TDocVariantData array from a given variant instance
// - return true and set DV with a pointer to the TDocVariantData
// corresponding to the variant instance, if it is a dvArray
// - return false if the supplied Value is not an array TDocVariant
// - note: due to a local variable lifetime change in Delphi 11, don't use
// this function with a temporary variant (e.g. from TList<variant>.GetItem) -
// call _DV() and a local TDocVariantData instead of a PDocVariantData
/// 从给定的变体实例直接访问 TDocVariantData 数组
// - 返回 true 并设置 DV 为指向对应于变体实例的 TDocVariantData 的指针（如果它是 dvArray）
// - 如果提供的 Value 不是数组 TDocVariant，则返回 false
// - 注意：由于 Delphi 11 中的局部变量生命周期发生变化，请勿将此函数与临时变量一起使用（例如，来自 TList<variant>.GetItem） - 调用 _DV() 和本地 TDocVariantData 而不是 PDocVariantData
function _SafeArray(const Value: variant; out DV: PDocVariantData): boolean; overload;

/// direct access to a TDocVariantData array from a given variant instance
// - overload to check for a given number of itemsin the array
/// 从给定的变体实例直接访问 TDocVariantData 数组
// - 重载以检查数组中给定数量的项目
function _SafeArray(const Value: variant; ExpectedCount: integer;
  out DV: PDocVariantData): boolean; overload;

/// direct access to a TDocVariantData object from a given variant instance
// - return true and set DV with a pointer to the TDocVariantData
// corresponding to the variant instance, if it is a dvObject
// - return false if the supplied Value is not an object TDocVariant
// - note: due to a local variable lifetime change in Delphi 11, don't use
// this function with a temporary variant (e.g. from TList<variant>.GetItem) -
// call _DV() and a local TDocVariantData instead of a PDocVariantData
/// 从给定的变体实例直接访问 TDocVariantData 对象
// - 返回 true 并使用指向对应于变体实例的 TDocVariantData 的指针设置 DV（如果它是 dvObject）
// - 如果提供的 Value 不是对象 TDocVariant，则返回 false
// - 注意：由于 Delphi 11 中的局部变量生命周期发生变化，请勿将此函数与临时变量一起使用（例如，来自 TList<variant>.GetItem） - 调用 _DV() 和本地 TDocVariantData 而不是 PDocVariantData
function _SafeObject(const Value: variant; out DV: PDocVariantData): boolean;

/// direct copy of a TDocVariantData from a given variant instance
// - slower, but maybe used instead of _Safe() e.g. on Delphi 11
/// 从给定变体实例直接复制 TDocVariantData
// - 速度较慢，但可以代替 _Safe() 使用，例如 在Delphi 11 上
function _DV(const DocVariant: variant): TDocVariantData; overload;
  {$ifdef HASINLINE}inline;{$endif}

/// direct copy of a TDocVariantData from a given variant instance
// - slower, but maybe used instead of _Safe() e.g. on Delphi 11
/// 从给定变体实例直接复制 TDocVariantData
// - 速度较慢，但可以代替 _Safe() 使用，例如 在 Delphi 11 上
function _DV(const DocVariant: variant;
  ExpectedKind: TDocVariantKind): TDocVariantData; overload;
  {$ifdef HASINLINE}inline;{$endif}

/// direct copy of a TDocVariantData from a given variant instance
// - slower, but maybe used instead of _Safe() e.g. on Delphi 11
/// 从给定变体实例直接复制 TDocVariantData
// - 速度较慢，但可以代替 _Safe() 使用，例如 Delphi 11 上
function _DV(const DocVariant: variant;
  var DV: TDocVariantData): boolean; overload;
  {$ifdef FPC}inline;{$endif} // Delphi has troubles inlining goto/label

/// initialize a variant instance to store some document-based object content
// - object will be initialized with data supplied two by two, as Name,Value
// pairs, e.g.
// ! aVariant := _Obj(['name','John','year',1972]);
// or even with nested objects:
// ! aVariant := _Obj(['name','John','doc',_Obj(['one',1,'two',2.0])]);
// - this global function is an alias to TDocVariant.NewObject()
// - by default, every internal value will be copied, so access of nested
// properties can be slow - if you expect the data to be read-only or not
// propagated into another place, set Options=[dvoValueCopiedByReference]
// or using _ObjFast() will increase the process speed a lot
/// 初始化一个变体实例来存储一些基于文档的对象内容
// - 对象将使用两两提供的数据进行初始化，如名称、值对，例如
// ! aVariant := _Obj(['name','John','year',1972]);
// 或者甚至使用嵌套对象：
// ! aVariant := _Obj(['name','John','doc',_Obj(['one',1,'two',2.0])]);
// - 此全局函数是 TDocVariant.NewObject() 的别名
// - 默认情况下，每个内部值都会被复制，因此嵌套属性的访问可能会很慢 - 如果您希望数据是只读的或不传播到另一个地方，请设置 Options=[dvoValueCopiedByReference] 或使用 _ObjFast() 会大大提高处理速度
function _Obj(const NameValuePairs: array of const;
  Options: TDocVariantOptions = []): variant;

/// add a property value to a document-based object content
// - if Obj is a TDocVariant object, will add the Name/Value pair
// - if Obj is not a TDocVariant, will create a new fast document,
// initialized with supplied the Name/Value pairs
// - this function will also ensure that ensure Obj is not stored by reference,
// but as a true TDocVariantData
/// 将属性值添加到基于文档的对象内容
// - 如果 Obj 是 TDocVariant 对象，将添加名称/值对
// - 如果 Obj 不是 TDocVariant，将创建一个新的快速文档，并使用提供的名称/值对进行初始化
// - 该函数还将确保确保 Obj 不是通过引用存储，而是作为真正的 TDocVariantData
procedure _ObjAddProp(const Name: RawUtf8; const Value: variant;
  var Obj: variant); overload;

/// add a document property value to a document-based object content
/// 将文档属性值添加到基于文档的对象内容
procedure _ObjAddProp(const Name: RawUtf8; const Value: TDocVariantData;
  var Obj: variant); overload;
  {$ifdef HASINLINE} inline; {$endif}

/// add a RawUtf8 property value to a document-based object content
/// 将 RawUtf8 属性值添加到基于文档的对象内容
procedure _ObjAddPropU(const Name: RawUtf8; const Value: RawUtf8;
  var Obj: variant);

/// add some property values to a document-based object content
// - if Obj is a TDocVariant object, will add the Name/Value pairs
// - if Obj is not a TDocVariant, will create a new fast document,
// initialized with supplied the Name/Value pairs
// - this function will also ensure that ensure Obj is not stored by reference,
// but as a true TDocVariantData
/// 添加一些属性值到基于文档的对象内容
// - 如果 Obj 是 TDocVariant 对象，将添加名称/值对
// - 如果 Obj 不是 TDocVariant，将创建一个新的快速文档，并使用提供的名称/值对进行初始化
// - 该函数还将确保确保 Obj 不是通过引用存储，而是作为真正的 TDocVariantData
procedure _ObjAddProps(const NameValuePairs: array of const;
  var Obj: variant); overload;

/// add the property values of a document to a document-based object content
// - if Document is not a TDocVariant object, will do nothing
// - if Obj is a TDocVariant object, will add Document fields to its content
// - if Obj is not a TDocVariant object, Document will be copied to Obj
/// 将文档的属性值添加到基于文档的对象内容
// - 如果 Document 不是 TDocVariant 对象，则不执行任何操作
// - 如果 Obj 是 TDocVariant 对象，则会将文档字段添加到其内容中
// - 如果 Obj 不是 TDocVariant 对象，Document 将被复制到 Obj
procedure _ObjAddProps(const Document: variant;
  var Obj: variant); overload;

/// initialize a variant instance to store some document-based array content
// - array will be initialized with data supplied as parameters, e.g.
// ! aVariant := _Arr(['one',2,3.0]);
// - this global function is an alias to TDocVariant.NewArray()
// - by default, every internal value will be copied, so access of nested
// properties can be slow - if you expect the data to be read-only or not
// propagated into another place, set Options = [dvoValueCopiedByReference]
// or using _ArrFast() will increase the process speed a lot
/// 初始化一个变体实例来存储一些基于文档的数组内容
// - 数组将使用作为参数提供的数据进行初始化，例如
//！ aVariant := _Arr(['一',2,3.0]);
// - 此全局函数是 TDocVariant.NewArray() 的别名
// - 默认情况下，每个内部值都会被复制，因此嵌套属性的访问可能会很慢 - 如果您希望数据是只读的或不传播到另一个地方，请设置 Options = [dvoValueCopiedByReference] 或使用 _ArrFast() 会大大提高处理速度
function _Arr(const Items: array of const;
  Options: TDocVariantOptions = []): variant;

/// initialize a variant instance to store some document-based content
// from a supplied (extended) JSON content
// - this global function is an alias to TDocVariant.NewJson(), and
// will return an Unassigned variant if JSON content was not correctly converted
// - object or array will be initialized from the supplied JSON content, e.g.
// ! aVariant := _Json('{"id":10,"doc":{"name":"John","birthyear":1972}}');
// ! // now you can access to the properties via late binding
// ! assert(aVariant.id=10);
// ! assert(aVariant.doc.name='John');
// ! assert(aVariant.doc.birthYear=1972);
// ! // and also some pseudo-properties:
// ! assert(aVariant._count=2);
// ! assert(aVariant.doc._kind=ord(dvObject));
// ! // or with a JSON array:
// ! aVariant := _Json('["one",2,3]');
// ! assert(aVariant._kind=ord(dvArray));
// ! for i := 0 to aVariant._count-1 do
// !   writeln(aVariant._(i));
// - in addition to the JSON RFC specification strict mode, this method will
// handle some BSON-like extensions, e.g. unquoted field names:
// ! aVariant := _Json('{id:10,doc:{name:"John",birthyear:1972}}');
// - if the mormot.db.nosql.bson unit is used in the application, the MongoDB
// Shell syntax will also be recognized to create TBsonVariant, like
// ! new Date()   ObjectId()   MinKey   MaxKey  /<jRegex>/<jOptions>
// see @http://docs.mongodb.org/manual/reference/mongodb-extended-json
// - by default, every internal value will be copied, so access of nested
// properties can be slow - if you expect the data to be read-only or not
// propagated into another place, add dvoValueCopiedByReference in Options
// will increase the process speed a lot, or use _JsonFast()
// - handle only currency for floating point values: call _JsonFastFloat or set
// dvoAllowDoubleValue option to support double, with potential precision loss
/// 初始化变体实例以存储来自提供的（扩展）JSON 内容的一些基于文档的内容
// - 此全局函数是 TDocVariant.NewJson() 的别名，如果 JSON 内容未正确转换，将返回未分配的变体
// - 对象或数组将从提供的 JSON 内容初始化，例如
// ! aVariant := _Json('{"id":10,"doc":{"name":"John","birthyear":1972}}');
// ! // now you can access to the properties via late binding
// ! assert(aVariant.id=10);
// ! assert(aVariant.doc.name='John');
// ! assert(aVariant.doc.birthYear=1972);
// ! // and also some pseudo-properties:
// ! assert(aVariant._count=2);
// ! assert(aVariant.doc._kind=ord(dvObject));
// ! // or with a JSON array:
// ! aVariant := _Json('["one",2,3]');
// ! assert(aVariant._kind=ord(dvArray));
// ! for i := 0 to aVariant._count-1 do
// !   writeln(aVariant._(i));
// - 除了 JSON RFC 规范严格模式之外，此方法还将处理一些类似 BSON 的扩展，例如 不带引号的字段名称：
// ! aVariant := _Json('{id:10,doc:{name:"John",birthyear:1972}}');
// - 如果应用程序中使用了 mormot.db.nosql.bson 单元，MongoDB Shell 语法也将被识别以创建 TBsonVariant，
// 如 ! new Date() ObjectId() MinKey MaxKey /<jRegex>/<jOptions> 
// 请参阅@http://docs.mongodb.org/manual/reference/mongodb-extended-json
// - 默认情况下，每个内部值都会被复制，因此嵌套属性的访问可能会很慢 - 如果您希望数据是只读的或不传播到另一个地方，
// 在选项中添加 dvoValueCopiedByReference 将大大提高处理速度 ，或使用 _JsonFast()
// - 仅处理浮点值的货币：调用 _JsonFastFloat 或设置 dvoAllowDoubleValue 选项以支持双精度，但可能会导致精度损失
function _Json(const Json: RawUtf8;
  Options: TDocVariantOptions = [dvoReturnNullForUnknownProperty]): variant; overload;
  {$ifdef HASINLINE}inline;{$endif}

/// initialize a variant instance to store some document-based content
// from a supplied (extended) JSON content, with parameters formating
// - wrapper around the _Json(FormatUtf8(...,JsonFormat=true)) function,
// i.e. every Args[] will be inserted for each % and Params[] for each ?,
// with proper JSON escaping of string values, and writing nested _Obj() /
// _Arr() instances as expected JSON objects / arrays
// - typical use (in the context of mormot.db.nosql.bson unit) could be:
// ! aVariant := _JsonFmt('{%:{$in:[?,?]}}',['type'],['food','snack']);
// ! aVariant := _JsonFmt('{type:{$in:?}}',[],[_Arr(['food','snack'])]);
// ! // which are the same as:
// ! aVariant := _JsonFmt('{type:{$in:["food","snack"]}}');
// ! // in this context:
// ! u := VariantSaveJson(aVariant);
// ! assert(u='{"type":{"$in":["food","snack"]}}');
// ! u := VariantSaveMongoJson(aVariant,modMongoShell);
// ! assert(u='{type:{$in:["food","snack"]}}');
// - by default, every internal value will be copied, so access of nested
// properties can be slow - if you expect the data to be read-only or not
// propagated into another place, add dvoValueCopiedByReference in Options
// will increase the process speed a lot, or use _JsonFast()
/// 初始化变体实例以存储来自提供的（扩展）JSON 内容的一些基于文档的内容，并带有参数格式
// - _Json(FormatUtf8(...,JsonFormat=true)) 函数的包装，即为每个 % 插入每个 Args[]，为每个 ? 插入 Params[]，
// 并使用正确的 JSON 转义字符串值，并写入 嵌套 _Obj() / _Arr() 实例作为预期的 JSON 对象/数组
// - 典型用法（在 mormot.db.nosql.bson 单元的上下文中）可能是：
// ! aVariant := _JsonFmt('{%:{$in:[?,?]}}',['type'],['food','snack']);
// ! aVariant := _JsonFmt('{type:{$in:?}}',[],[_Arr(['food','snack'])]);
// ! // which are the same as:
// ! aVariant := _JsonFmt('{type:{$in:["food","snack"]}}');
// ! // in this context:
// ! u := VariantSaveJson(aVariant);
// ! assert(u='{"type":{"$in":["food","snack"]}}');
// ! u := VariantSaveMongoJson(aVariant,modMongoShell);
// ! assert(u='{type:{$in:["food","snack"]}}');
// - 默认情况下，每个内部值都会被复制，因此嵌套属性的访问可能会很慢 - 如果您希望数据是只读的或不传播到另一个地方，
// 在选项中添加 dvoValueCopiedByReference 将大大提高处理速度 ，或使用 _JsonFast()
function _JsonFmt(const Format: RawUtf8; const Args, Params: array of const;
  Options: TDocVariantOptions = [dvoReturnNullForUnknownProperty]): variant; overload;

/// initialize a variant instance to store some document-based content
// from a supplied (extended) JSON content, with parameters formating
// - this overload function will set directly a local variant variable,
// and would be used by inlined _JsonFmt/_JsonFastFmt functions
/// 初始化变体实例以存储来自提供的（扩展）JSON 内容的一些基于文档的内容，并带有参数格式
// - 此重载函数将直接设置局部变量变量，并将由内联 _JsonFmt/_JsonFastFmt 函数使用
procedure _JsonFmt(const Format: RawUtf8; const Args, Params: array of const;
  Options: TDocVariantOptions; out Result: variant); overload;

/// initialize a variant instance to store some document-based content
// from a supplied (extended) JSON content
// - this global function is an alias to TDocVariant.NewJson(), and
// will return TRUE if JSON content was correctly converted into a variant
// - in addition to the JSON RFC specification strict mode, this method will
// handle some BSON-like extensions, e.g. unquoted field names or ObjectID()
// - by default, every internal value will be copied, so access of nested
// properties can be slow - if you expect the data to be read-only or not
// propagated into another place, add dvoValueCopiedByReference in Options
// will increase the process speed a lot, or use _JsonFast()
/// 初始化变体实例以存储来自提供的（扩展）JSON 内容的一些基于文档的内容
// - 此全局函数是 TDocVariant.NewJson() 的别名，如果 JSON 内容正确转换为变体，则返回 TRUE
// - 除了 JSON RFC 规范严格模式之外，此方法还将处理一些类似 BSON 的扩展，例如 不带引号的字段名称或 ObjectID()
// - 默认情况下，每个内部值都会被复制，因此嵌套属性的访问可能会很慢 - 如果您希望数据是只读的或不传播到另一个地方，
// 在选项中添加 dvoValueCopiedByReference 将大大提高处理速度 ，或使用 _JsonFast()
function _Json(const Json: RawUtf8; var Value: variant;
  Options: TDocVariantOptions = [dvoReturnNullForUnknownProperty]): boolean; overload;

/// initialize a variant instance to store some document-based object content
// - this global function is an handy alias to:
// ! Obj(NameValuePairs, JSON_FAST);
// - so all created objects and arrays will be handled by reference, for best
// speed - but you should better write on the resulting variant tree with caution
/// 初始化一个变体实例来存储一些基于文档的对象内容
// - 这个全局函数是一个方便的别名：
//！ Obj(NameValuePairs, JSON_FAST);
// - 因此，为了获得最佳速度，所有创建的对象和数组都将通过引用处理 - 但您最好小心地在生成的变体树上写入
function _ObjFast(const NameValuePairs: array of const): variant; overload;

/// initialize a variant instance to store any object as a TDocVariant
// - is a wrapper around ObjectToVariant(aObject, result, aOptions)
/// 初始化变体实例以将任何对象存储为 TDocVariant
// - 是 ObjectToVariant(aObject, result, aOptions) 的包装
function _ObjFast(aObject: TObject;
   aOptions: TTextWriterWriteObjectOptions = [woDontStoreDefault]): variant; overload;
  {$ifdef HASINLINE}inline;{$endif}

/// initialize a variant instance to store some document-based array content
// - this global function is an handy alias to:
// ! _Array(Items, JSON_FAST);
// - so all created objects and arrays will be handled by reference, for best
// speed - but you should better write on the resulting variant tree with caution
/// 初始化一个变体实例来存储一些基于文档的数组内容
// - 这个全局函数是一个方便的别名：
//！ _Array(项目, JSON_FAST);
// - 因此，为了获得最佳速度，所有创建的对象和数组都将通过引用处理 - 但您最好小心地在生成的变体树上写入
function _ArrFast(const Items: array of const): variant; overload;

/// initialize a variant instance to store some document-based content
// from a supplied (extended) JSON content
// - this global function is an handy alias to:
// ! _Json(JSON, JSON_FAST);
// so it will return an Unassigned variant if JSON content was not correct
// - so all created objects and arrays will be handled by reference, for best
// speed - but you should better write on the resulting variant tree with caution
// - in addition to the JSON RFC specification strict mode, this method will
// handle some BSON-like extensions, e.g. unquoted field names or ObjectID()
// - will handle only currency for floating point values to avoid precision
// loss: use _JsonFastFloat() instead if you want to support double values
/// 初始化变体实例以存储来自提供的（扩展）JSON 内容的一些基于文档的内容
// - 这个全局函数是一个方便的别名：
// ! _Json(JSON, JSON_FAST);
// 因此，如果 JSON 内容不正确，它将返回未分配的变体
// - 因此，为了获得最佳速度，所有创建的对象和数组都将通过引用处理 - 但您最好小心地在生成的变体树上写入
// - 除了 JSON RFC 规范严格模式之外，此方法还将处理一些类似 BSON 的扩展，例如 不带引号的字段名称或 ObjectID()
// - 将仅处理浮点值的货币以避免精度损失：如果您想支持双精度值，请使用 _JsonFastFloat()
function _JsonFast(const Json: RawUtf8): variant;

/// initialize a variant instance to store some document-based content
// from a supplied (extended) JSON content, with double conversion
// - _JsonFast() will support only currency floats: use this method instead
// if your JSON input is likely to require double values - with potential
// precision loss
/// 初始化变体实例以存储来自提供的（扩展）JSON 内容的一些基于文档的内容，并进行双重转换
// - _JsonFast() 将仅支持货币浮动：如果您的 JSON 输入可能需要双精度值，则使用此方法 - 可能会导致精度损失
function _JsonFastFloat(const Json: RawUtf8): variant;

/// initialize a variant instance to store some extended document-based content
// - this global function is an handy alias to:
// ! _Json(JSON, JSON_FAST_EXTENDED);
/// 初始化一个变体实例来存储一些扩展的基于文档的内容
// - 这个全局函数是一个方便的别名：
// ! _Json(JSON, JSON_FAST_EXTENDED);
function _JsonFastExt(const Json: RawUtf8): variant;

/// initialize a variant instance to store some document-based content
// from a supplied (extended) JSON content, with parameters formating
// - this global function is an handy alias e.g. to:
// ! aVariant := _JsonFmt('{%:{$in:[?,?]}}',['type'],['food','snack'], JSON_FAST);
// - so all created objects and arrays will be handled by reference, for best
// speed - but you should better write on the resulting variant tree with caution
// - in addition to the JSON RFC specification strict mode, this method will
// handle some BSON-like extensions, e.g. unquoted field names or ObjectID():
/// 初始化变体实例以存储来自提供的（扩展）JSON 内容的一些基于文档的内容，并带有参数格式
// - 这个全局函数是一个方便的别名，例如 到：
// ! aVariant := _JsonFmt('{%:{$in:[?,?]}}',['type'],['food','snack'], JSON_FAST);
// - 因此，为了获得最佳速度，所有创建的对象和数组都将通过引用处理 - 但您最好小心地在生成的变体树上写入
// - 除了 JSON RFC 规范严格模式之外，此方法还将处理一些类似 BSON 的扩展，例如 不带引号的字段名称或 ObjectID()：
function _JsonFastFmt(const Format: RawUtf8;
   const Args, Params: array of const): variant;

/// ensure a document-based variant instance will have only per-value nested
// objects or array documents
// - is just a wrapper around:
// ! TDocVariantData(DocVariant).InitCopy(DocVariant, JSON_[mDefault])
// - you can use this function to ensure that all internal properties of this
// variant will be copied per-value whatever options the nested objects or
// arrays were created with
// - for huge document with a big depth of nested objects or arrays, a full
// per-value copy may be time and resource consuming, but will be also safe
// - will raise an EDocVariant if the supplied variant is not a TDocVariant or
// a varByRef pointing to a TDocVariant
/// 确保基于文档的变体实例仅具有每个值嵌套对象或数组文档
// - 只是一个包装：
// ! TDocVariantData(DocVariant).InitCopy(DocVariant, JSON_[mDefault])
// - 您可以使用此函数来确保此变体的所有内部属性都将按值复制，无论嵌套对象或数组是使用什么选项创建的
// - 对于具有大深度嵌套对象或数组的大型文档，完整的每个值复制可能会消耗时间和资源，但也很安全
// - 如果提供的变体不是 TDocVariant 或指向 TDocVariant 的 varByRef，则将引发 EDocVariant
procedure _Unique(var DocVariant: variant);

/// ensure a document-based variant instance will have only per-value nested
// objects or array documents
// - is just a wrapper around:
// ! TDocVariantData(DocVariant).InitCopy(DocVariant, JSON_FAST)
// - you can use this function to ensure that all internal properties of this
// variant will be copied per-reference whatever options the nested objects or
// arrays were created with
// - for huge document with a big depth of nested objects or arrays, it will
// first create a whole copy of the document nodes, but further assignments
// of the resulting value will be per-reference, so will be almost instant
// - will raise an EDocVariant if the supplied variant is not a TDocVariant or
// a varByRef pointing to a TDocVariant
/// 确保基于文档的变体实例仅具有每个值嵌套对象或数组文档
// - 只是一个包装：
// ! TDocVariantData(DocVariant).InitCopy(DocVariant, JSON_FAST)
// - 您可以使用此函数来确保此变体的所有内部属性都将按引用复制，无论嵌套对象或数组是使用什么选项创建的
// - 对于具有大深度嵌套对象或数组的大型文档，它将首先创建文档节点的完整副本，但结果值的进一步分配将是针对每个引用的，因此几乎是即时的
// - 如果提供的变体不是 TDocVariant 或指向 TDocVariant 的 varByRef，则将引发 EDocVariant
procedure _UniqueFast(var DocVariant: variant);

/// return a full nested copy of a document-based variant instance
// - is just a wrapper around:
// ! TDocVariant.NewUnique(DocVariant,JSON_[mDefault])
// - you can use this function to ensure that all internal properties of this
// variant will be copied per-value whatever options the nested objects or
// arrays were created with: to be used on a value returned as varByRef
// (e.g. by _() pseudo-method)
// - for huge document with a big depth of nested objects or arrays, a full
// per-value copy may be time and resource consuming, but will be also safe -
// consider using _ByRef() instead if a fast copy-by-reference is enough
// - will raise an EDocVariant if the supplied variant is not a TDocVariant or
// a varByRef pointing to a TDocVariant
/// 返回基于文档的变体实例的完整嵌套副本
// - 只是一个包装：
// ! TDocVariant.NewUnique(DocVariant,JSON_[mDefault])
// - 您可以使用此函数来确保此变体的所有内部属性都将按值复制，无论创建嵌套对象或数组时使用什么选项：用于以 varByRef 返回的值（例如，通过 _() 伪值） -方法）
// - 对于具有大深度嵌套对象或数组的大型文档，完整的按值复制可能会消耗时间和资源，但也很安全 - 如果需要快速按引用复制，请考虑使用 _ByRef() 足够的
// - 如果提供的变体不是 TDocVariant 或指向 TDocVariant 的 varByRef，则将引发 EDocVariant
function _Copy(const DocVariant: variant): variant;

/// return a full nested copy of a document-based variant instance
// - is just a wrapper around:
// ! TDocVariant.NewUnique(DocVariant, JSON_FAST)
// - you can use this function to ensure that all internal properties of this
// variant will be copied per-value whatever options the nested objects or
// arrays were created with: to be used on a value returned as varByRef
// (e.g. by _() pseudo-method)
// - for huge document with a big depth of nested objects or arrays, a full
// per-value copy may be time and resource consuming, but will be also safe -
// consider using _ByRef() instead if a fast copy-by-reference is enough
// - will raise an EDocVariant if the supplied variant is not a TDocVariant or
// a varByRef pointing to a TDocVariant
/// 返回基于文档的变体实例的完整嵌套副本
// - 只是一个包装：
// ! TDocVariant.NewUnique(DocVariant, JSON_FAST)
// - 您可以使用此函数来确保此变体的所有内部属性都将按值复制，无论创建嵌套对象或数组时使用什么选项：用于以 varByRef 返回的值（例如，通过 _() 伪值） -方法）
// - 对于具有大深度嵌套对象或数组的大型文档，完整的按值复制可能会消耗时间和资源，但也很安全 - 如果需要快速按引用复制，请考虑使用 _ByRef() 足够的
// - 如果提供的变体不是 TDocVariant 或指向 TDocVariant 的 varByRef，则将引发 EDocVariant
function _CopyFast(const DocVariant: variant): variant;

/// copy a TDocVariant to another variable, changing the options on the fly
// - note that the content (items or properties) is copied by reference,
// so consider using _Copy() instead if you expect to safely modify its content
// - will return null if the supplied variant is not a TDocVariant
/// 将 TDocVariant 复制到另一个变量，动态更改选项
// - 请注意，内容（项目或属性）是通过引用复制的，因此如果您希望安全地修改其内容，请考虑使用 _Copy()
// - 如果提供的变体不是 TDocVariant，将返回 null
function _ByRef(const DocVariant: variant;
   Options: TDocVariantOptions): variant; overload;

/// copy a TDocVariant to another variable, changing the options on the fly
// - note that the content (items or properties) is copied by reference,
// so consider using _Copy() instead if you expect to safely modify its content
// - will return null if the supplied variant is not a TDocVariant
/// 将 TDocVariant 复制到另一个变量，动态更改选项
// - 请注意，内容（项目或属性）是通过引用复制的，因此如果您希望安全地修改其内容，请考虑使用 _Copy()
// - 如果提供的变体不是 TDocVariant，将返回 null
procedure _ByRef(const DocVariant: variant; out Dest: variant;
  Options: TDocVariantOptions); overload;

/// convert a TDocVariantData array or a string value into a CSV
// - will call either TDocVariantData.ToCsv, or return the string
// - returns '' if the supplied value is neither a TDocVariant or a string
// - could be used e.g. to store either a JSON CSV string or a JSON array of
// strings in a settings property
/// 将 TDocVariantData 数组或字符串值转换为 CSV
// - 将调用 TDocVariantData.ToCsv，或返回字符串
// - 如果提供的值既不是 TDocVariant 也不是字符串，则返回 ''
// - 可以使用，例如 在设置属性中存储 JSON CSV 字符串或 JSON 字符串数组
function _Csv(const DocVariantOrString: variant): RawUtf8;

/// will convert any TObject into a TDocVariant document instance
// - fast processing function as used by _ObjFast(Value)
// - note that the result variable should already be cleared: no VarClear()
// is done by this function
// - would be used e.g. by VarRecToVariant() function
// - if you expect lazy-loading of a TObject, see TObjectVariant.New()
/// 将任何 TObject 转换为 TDocVariant 文档实例
// - _ObjFast(Value) 使用的快速处理函数
// - 请注意，结果变量应该已经被清除：此函数没有执行 VarClear()
// - 将被使用，例如 通过 VarRecToVariant() 函数
// - 如果您希望延迟加载 TObject，请参阅 TObjectVariant.New()
procedure ObjectToVariant(Value: TObject; var result: variant;
  Options: TTextWriterWriteObjectOptions = [woDontStoreDefault]); overload;

/// will convert any TObject into a TDocVariant document instance
// - convenient overloaded function to include woEnumSetsAsText option
/// 将任何 TObject 转换为 TDocVariant 文档实例
// - 方便的重载函数包含 woEnumSetsAsText 选项
function ObjectToVariant(Value: TObject; EnumSetsAsText: boolean): variant; overload;

/// will serialize any TObject into a TDocVariant debugging document
// - just a wrapper around _JsonFast(ObjectToJsonDebug()) with an optional
// "Context":"..." text message
// - if the supplied context format matches '{....}' then it will be added
// as a corresponding TDocVariant JSON object
/// 将任何 TObject 序列化为 TDocVariant 调试文档
// - 只是 _JsonFast(ObjectToJsonDebug()) 的包装，带有可选的 "Context":"..." 文本消息
// - 如果提供的上下文格式与 '{....}' 匹配，那么它将被添加为相应的 TDocVariant JSON 对象
function ObjectToVariantDebug(Value: TObject;
  const ContextFormat: RawUtf8; const ContextArgs: array of const;
  const ContextName: RawUtf8 = 'context'): variant; overload;

/// get the enumeration names corresponding to a set value, as a JSON array
/// 获取与设置值对应的枚举名称，作为 JSON 数组
function SetNameToVariant(Value: cardinal; Info: TRttiCustom;
  FullSetsAsStar: boolean = false): variant; overload;

/// get the enumeration names corresponding to a set value, as a JSON array
/// 获取与设置值对应的枚举名称，作为 JSON 数组
function SetNameToVariant(Value: cardinal; Info: PRttiInfo;
  FullSetsAsStar: boolean = false): variant; overload;

/// fill a class instance from a TDocVariant object document properties
// - returns FALSE if the variant is not a dvObject, TRUE otherwise
/// 从 TDocVariant 对象文档属性中填充类实例
// - 如果变体不是 dvObject，则返回 FALSE，否则返回 TRUE
function DocVariantToObject(var doc: TDocVariantData; obj: TObject;
  objRtti: TRttiCustom = nil): boolean;

/// fill a T*ObjArray variable from a TDocVariant array document values
// - will always erase the T*ObjArray instance, and fill it from arr values
/// 从 TDocVariant 数组文档值填充 T*ObjArray 变量
// - 将始终删除 T*ObjArray 实例，并从 arr 值填充它
procedure DocVariantToObjArray(var arr: TDocVariantData; var objArray;
  objClass: TClass);

/// will convert a blank TObject into a TDocVariant document instance
/// 将空白 TObject 转换为 TDocVariant 文档实例
function ObjectDefaultToVariant(aClass: TClass;
  aOptions: TDocVariantOptions): variant; overload;



{ ************** JSON Parsing into Variant }
{ ************** JSON 解析为变体 }

/// low-level function to set a variant from an unescaped JSON number or string
// - expect the JSON input buffer to be already unescaped and #0 terminated,
// e.g. by TGetJsonField, and having set properly the wasString flag
// - set the varString or call GetVariantFromNotStringJson() if TryCustomVariants=nil
// - or call GetJsonToAnyVariant() to support TryCustomVariants^ complex input
/// 从未转义的 JSON 数字或字符串设置变体的低级函数
// - 期望 JSON 输入缓冲区已经未转义并且 #0 终止，例如 通过 TGetJsonField，并正确设置 wasString 标志
// - 如果 TryCustomVariants=nil，则设置 varString 或调用 GetVariantFromNotStringJson()
// - 或调用 GetJsonToAnyVariant() 以支持 TryCustomVariants^ 复杂输入
procedure GetVariantFromJsonField(Json: PUtf8Char; wasString: boolean;
  var Value: variant; TryCustomVariants: PDocVariantOptions = nil;
  AllowDouble: boolean = false; JsonLen: integer = 0);

/// low-level function to set a variant from an unescaped JSON non string
// - expect the JSON input buffer to be already unescaped and #0 terminated,
// e.g. by TGetJsonField, and having returned wasString=false
// - is called e.g. by function GetVariantFromJsonField()
// - will recognize null, boolean, integer, Int64, currency, double
// (if AllowDouble is true) input, then set Value and return TRUE
// - returns FALSE if the supplied input has no expected JSON format
/// 用于设置未转义 JSON 非字符串变体的低级函数
// - 期望 JSON 输入缓冲区已经未转义并且 #0 终止，例如 通过 TGetJsonField，并返回 wasString=false
// - 被称为例如 通过函数 GetVariantFromJsonField()
// - 将识别 null、boolean、integer、Int64、currency、double（如果 AllowDouble 为 true）输入，然后设置 Value 并返回 TRUE
// - 如果提供的输入没有预期的 JSON 格式，则返回 FALSE
function GetVariantFromNotStringJson(Json: PUtf8Char;
  var Value: TVarData; AllowDouble: boolean): boolean;
  {$ifdef HASINLINE}inline;{$endif}

/// low-level function to parse a JSON buffer content into a variant
// - warning: will decode in the Json buffer memory itself (no memory
// allocation or copy), for faster process - so take care that it is not shared
// - internal method used by VariantLoadJson(), GetVariantFromJsonField() and
// TDocVariantData.InitJson()
// - will instantiate either an integer, Int64, currency, double or string value
// (as RawUtf8), guessing the best numeric type according to the textual content,
// and string in all other cases, except TryCustomVariants points to some options
// (e.g. @JSON_[mFast] for fast instance) and input is a known object or
// array, either encoded as strict-JSON (i.e. {..} or [..]), or with some
// extended (e.g. BSON) syntax
/// 将 JSON 缓冲区内容解析为变体的低级函数
// - 警告：将在 Json 缓冲区内存本身中进行解码（无内存分配或复制），以加快处理速度 - 因此请注意它不被共享
// - VariantLoadJson()、GetVariantFromJsonField() 和 TDocVariantData.InitJson() 使用的内部方法
// - 将实例化整数、Int64、货币、双精度或字符串值（如 RawUtf8），根据文本内容猜测最佳数字类型，
// 并在所有其他情况下实例化字符串，除了 TryCustomVariants 指向某些选项（例如 @JSON_ [mFast] 用于快速实例），
// 输入是已知对象或数组，编码为严格 JSON（即 {..} 或 [..]），或使用某些扩展（例如 BSON）语法
procedure JsonToAnyVariant(var Value: variant; var Info: TGetJsonField;
  Options: PDocVariantOptions; AllowDouble: boolean = false);

{$ifndef PUREMORMOT2}
/// low-level function to parse a JSON content into a variant
/// 将 JSON 内容解析为变体的低级函数
procedure GetJsonToAnyVariant(var Value: variant; var Json: PUtf8Char;
  EndOfObject: PUtf8Char; Options: PDocVariantOptions; AllowDouble: boolean);
    overload; {$ifdef HASINLINE}inline;{$endif}
{$endif PUREMORMOT2}

/// identify either varInt64, varDouble, varCurrency types following JSON format
// - any non valid number is returned as varString
// - warning: supplied JSON is expected to be not nil
/// 识别遵循 JSON 格式的 varInt64、varDouble、varCurrency 类型
// - 任何无效数字都作为 varString 返回
// - 警告：提供的 JSON 预计不为零
function TextToVariantNumberType(Json: PUtf8Char): cardinal;

/// identify either varInt64 or varCurrency types following JSON format
// - this version won't return varDouble, i.e. won't handle more than 4 exact
// decimals (as varCurrency), nor scientific notation with exponent (1.314e10)
// - this will ensure that any incoming JSON will converted back with its exact
// textual representation, without digit truncation due to limited precision
// - any non valid number is returned as varString
// - warning: supplied JSON is expected to be not nil
/// 识别遵循 JSON 格式的 varInt64 或 varCurrency 类型
// - 此版本不会返回 varDouble，即不会处理超过 4 位精确小数（如 varCurrency），也不会处理带指数的科学记数法 (1.314e10)
// - 这将确保任何传入的 JSON 都将转换回其精确的文本表示形式，而不会由于精度有限而导致数字截断
// - 任何无效数字都作为 varString 返回
// - 警告：提供的 JSON 预计不为零
function TextToVariantNumberTypeNoDouble(Json: PUtf8Char): cardinal;

/// low-level function to parse a variant from an unescaped JSON number
// - returns the position after the number, and set Value to a variant of type
// varInteger/varInt64/varCurrency (or varDouble if AllowVarDouble is true)
// - returns nil if JSON can't be converted to a number - it is likely a string
// - handle only up to 4 decimals (i.e. currency) if AllowVarDouble is false
// - matches TextToVariantNumberType/TextToVariantNumberTypeNoDouble() logic
// - see GetVariantFromNotStringJson() to check the whole Json input, and
// parse null/false/true values
/// 从未转义的 JSON 数字解析变体的低级函数
// - 返回数字后面的位置，并将 Value 设置为 varInteger/varInt64/varCurrency 类型的变体（如果 AllowVarDouble 为 true，则设置为 varDouble）
// - 如果 JSON 无法转换为数字，则返回 nil - 它可能是一个字符串
// - 如果AllowVarDouble为假，则仅处理最多4位小数（即货币）
// - 匹配 TextToVariantNumberType/TextToVariantNumberTypeNoDouble() 逻辑
// - 请参阅 GetVariantFromNotStringJson() 检查整个 Json 输入，并解析 null/false/true 值
function GetNumericVariantFromJson(Json: PUtf8Char;
  var Value: TVarData; AllowVarDouble: boolean): PUtf8Char;

/// convert some UTF-8 into a variant, detecting JSON numbers or constants
// - first try GetVariantFromNotStringJson() then fallback to RawUtf8ToVariant()
/// 将一些 UTF-8 转换为变体，检测 JSON 数字或常量
// - 首先尝试 GetVariantFromNotStringJson() 然后回退到 RawUtf8ToVariant()
procedure TextToVariant(const aValue: RawUtf8; AllowVarDouble: boolean;
  out aDest: variant);

/// convert some UTF-8 text buffer into a variant, with string interning
// - similar to TextToVariant(), but with string interning (if Interning<>nil)
// - first try GetVariantFromNotStringJson() then fallback to RawUtf8ToVariant()
/// 将一些 UTF-8 文本缓冲区转换为带有字符串驻留的变体
// - 与 TextToVariant() 类似，但具有字符串驻留（如果 Interning<>nil）
// - 首先尝试 GetVariantFromNotStringJson() 然后回退到 RawUtf8ToVariant()
procedure UniqueVariant(Interning: TRawUtf8Interning;
  var aResult: variant; aText: PUtf8Char; aTextLen: PtrInt;
  aAllowVarDouble: boolean = false); overload;

/// convert the next CSV item into a variant number or RawUtf8 varString
// - just a wrapper around GetNextItem() + TextToVariant()
/// 将下一个 CSV 项目转换为变体编号或 RawUtf8 varString
// - 只是 GetNextItem() + TextToVariant() 的包装
function GetNextItemToVariant(var P: PUtf8Char;
  out Value: Variant; Sep: AnsiChar = ','; AllowDouble: boolean = true): boolean;

/// retrieve a variant value from a JSON number or string
// - follows TJsonWriter.AddVariant() format (calls GetJsonToAnyVariant)
// - make a temporary copy before parsing - use GetJsonToAnyVariant() on a buffer
// - return true and set Value on success, or false and empty Value on error
/// 从 JSON 数字或字符串中检索变体值
// - 遵循 TJsonWriter.AddVariant() 格式（调用 GetJsonToAnyVariant）
// - 在解析之前制作临时副本 - 在缓冲区上使用 GetJsonToAnyVariant()
// - 成功时返回 true 并设置 Value，错误时返回 false 并设置为空 Value
function VariantLoadJson(var Value: Variant; const Json: RawUtf8;
  TryCustomVariants: PDocVariantOptions = nil;
  AllowDouble: boolean = false): boolean; overload;

/// retrieve a variant value from a JSON number or string
// - just wrap VariantLoadJson(Value,Json...) procedure as a function
/// 从 JSON 数字或字符串中检索变体值
// - 只需将 VariantLoadJson(Value,Json...) 过程包装为函数
function VariantLoadJson(const Json: RawUtf8;
  TryCustomVariants: PDocVariantOptions = nil;
  AllowDouble: boolean = false): variant; overload;
  {$ifdef HASINLINE} inline; {$endif}

/// just a wrapper around VariantLoadJson() with some TDocVariantOptions
// - make a temporary copy of the input Json before parsing
/// 只是 VariantLoadJson() 的包装，带有一些 TDocVariantOptions
// - 在解析之前制作输入 Json 的临时副本
function JsonToVariant(const Json: RawUtf8;
  Options: TDocVariantOptions = [dvoReturnNullForUnknownProperty];
  AllowDouble: boolean = false): variant;
  {$ifdef HASINLINE} inline; {$endif}

/// just a wrapper around GetJsonToAnyVariant() with some TDocVariantOptions
/// 只是 GetJsonToAnyVariant() 的包装，带有一些 TDocVariantOptions
function JsonToVariantInPlace(var Value: Variant; Json: PUtf8Char;
  Options: TDocVariantOptions = [dvoReturnNullForUnknownProperty];
  AllowDouble: boolean = false): PUtf8Char;
  {$ifdef HASINLINE} inline; {$endif}

/// decode multipart/form-data POST request content into a TDocVariantData
// - following RFC 1867
// - decoded sections are encoded as Doc JSON object with its textual values,
// or with nested objects, if the data was supplied as binary:
// ! {"name1":{"data":..,"filename":...,"contenttype":...},"name2":...}
/// 将 multipart/form-data POST 请求内容解码为 TDocVariantData
// - 遵循 RFC 1867
// - 解码后的部分使用其文本值或嵌套对象编码为 Doc JSON 对象（如果数据以二进制形式提供）：
// ! {"name1":{"data":..,"filename":...,"contenttype":...},"name2":...}
procedure MultiPartToDocVariant(const MultiPart: TMultiPartDynArray;
  var Doc: TDocVariantData; Options: PDocVariantOptions = nil);


{ ************** Variant Binary Serialization }
{ ************** 变体二进制序列化 }

{$ifndef PUREMORMOT2}

/// compute the number of bytes needed to save a Variant content
// using the VariantSave() function
// - will return 0 in case of an invalid (not handled) Variant type
// - deprecated function - use overloaded BinarySave() functions instead
/// 使用 VariantSave() 函数计算保存 Variant 内容所需的字节数
// - 如果 Variant 类型无效（未处理），将返回 0
// - 已弃用的函数 - 使用重载的 BinarySave() 函数代替
function VariantSaveLength(const Value: variant): integer; deprecated;
  {$ifdef HASINLINE}inline;{$endif}


/// save a Variant content into a destination memory buffer
// - Dest must be at least VariantSaveLength() bytes long
// - will handle standard Variant types and custom types (serialized as JSON)
// - will return nil in case of an invalid (not handled) Variant type
// - will use a proprietary binary format, with some variable-length encoding
// of the string length
// - warning: will encode generic string fields as within the variant type
// itself: using this function between UNICODE and NOT UNICODE
// versions of Delphi, will propably fail - you have been warned!
// - deprecated function - use overloaded BinarySave() functions instead
/// 将 Variant 内容保存到目标内存缓冲区中
// - Dest 的长度必须至少为 VariantSaveLength() 个字节
// - 将处理标准 Variant 类型和自定义类型（序列化为 JSON）
// - 如果 Variant 类型无效（未处理），将返回 nil
// - 将使用专有的二进制格式，并对字符串长度进行一些可变长度编码
// - 警告：将像变体类型本身一样对通用字符串字段进行编码：在 Delphi 的 UNICODE 和 NOT UNICODE 版本之间使用此函数，可能会失败 - 您已被警告！
// - 已弃用的函数 - 使用重载的 BinarySave() 函数代替
function VariantSave(const Value: variant; Dest: PAnsiChar): PAnsiChar;
  overload; deprecated;   {$ifdef HASINLINE}inline;{$endif}

{$endif PUREMORMOT2}

/// save a Variant content into a binary buffer
// - will handle standard Variant types and custom types (serialized as JSON)
// - will return '' in case of an invalid (not handled) Variant type
// - just a wrapper around VariantSaveLength()+VariantSave()
// - warning: will encode generic string fields as within the variant type
// itself: using this function between UNICODE and NOT UNICODE
// versions of Delphi, will propably fail - you have been warned!
// - is a wrapper around BinarySave(rkVariant)
/// 将 Variant 内容保存到二进制缓冲区中
// - 将处理标准 Variant 类型和自定义类型（序列化为 JSON）
// - 如果 Variant 类型无效（未处理），将返回 ''
// - 只是 VariantSaveLength()+VariantSave() 的包装
// - 警告：将像变体类型本身一样对通用字符串字段进行编码：在 Delphi 的 UNICODE 和 NOT UNICODE 版本之间使用此函数，可能会失败 - 您已被警告！
// - 是 BinarySave(rkVariant) 的包装
function VariantSave(const Value: variant): RawByteString; overload;
  {$ifdef HASINLINE}inline;{$endif}

/// retrieve a variant value from our optimized binary serialization format
// - follow the data layout as used by RecordLoad() or VariantSave() function
// - return nil if the Source buffer is incorrect
// - in case of success, return the memory buffer pointer just after the
// read content
// - how custom type variants are created can be defined via CustomVariantOptions
// - is a wrapper around BinaryLoad(rkVariant)
/// 从我们优化的二进制序列化格式中检索变体值
// - 遵循 RecordLoad() 或 VariantSave() 函数使用的数据布局
// - 如果源缓冲区不正确则返回 nil
// - 如果成功，则返回读取内容之后的内存缓冲区指针
// - 如何创建自定义类型变体可以通过 CustomVariantOptions 定义
// - 是 BinaryLoad(rkVariant) 的包装器
function VariantLoad(var Value: variant; Source: PAnsiChar;
  CustomVariantOptions: PDocVariantOptions;
  SourceMax: PAnsiChar {$ifndef PUREMORMOT2} = nil {$endif}): PAnsiChar; overload;

/// retrieve a variant value from our optimized binary serialization format
// - follow the data layout as used by RecordLoad() or VariantSave() function
// - return varEmpty if the Source buffer is incorrect
// - just a wrapper around VariantLoad()
// - how custom type variants are created can be defined via CustomVariantOptions
// - is a wrapper around BinaryLoad(rkVariant)
/// 从我们优化的二进制序列化格式中检索变体值
// - 遵循 RecordLoad() 或 VariantSave() 函数使用的数据布局
// - 如果源缓冲区不正确，则返回 varEmpty
// - 只是 VariantLoad() 的包装
// - 如何创建自定义类型变体可以通过 CustomVariantOptions 定义
// - 是 BinaryLoad(rkVariant) 的包装器
function VariantLoad(const Bin: RawByteString;
  CustomVariantOptions: PDocVariantOptions): variant; overload;
  {$ifdef HASINLINE}inline;{$endif}

/// retrieve a variant value from variable-length buffer
// - matches TFileBufferWriter.Write()
// - how custom type variants are created can be defined via CustomVariantOptions
// - is just a wrapper around VariantLoad/BinaryLoad
/// 从可变长度缓冲区中检索变体值
// - 匹配 TFileBufferWriter.Write()
// - 如何创建自定义类型变体可以通过 CustomVariantOptions 定义
// - 只是 VariantLoad/BinaryLoad 的包装
procedure FromVarVariant(var Source: PByte; var Value: variant;
  CustomVariantOptions: PDocVariantOptions; SourceMax: PByte);
  {$ifdef HASINLINE}inline;{$endif}


implementation


{ ************** Low-Level Variant Wrappers }
{ ************** 低级变体包装器 }

function VarIs(const V: Variant; const VTypes: TVarDataTypes): boolean;
var
  vd: PVarData;
  vt: cardinal;
begin
  vd := @V;
  repeat
    vt := vd^.VType;
    if vt <> varVariantByRef then
      break;
    vd := vd^.VPointer;
    if vd = nil then
    begin
      result := false;
      exit;
    end;
  until false;
  result := vt in VTypes;
end;

function VarIsVoid(const V: Variant): boolean;
var
  vt: cardinal;
  custom: TSynInvokeableVariantType;
begin
  vt := TVarData(V).VType;
  with TVarData(V) do
    case vt of
      varEmpty,
      varNull:
        result := true;
      varBoolean:
        result := not VBoolean;
      {$ifdef HASVARUSTRING}
      varUString,
      {$endif HASVARUSTRING}
      varString,
      varOleStr:
        result := VAny = nil;
      varDate:
        result := VInt64 = 0;
      // note: 0 as integer or float is considered as non-void
    else
      if vt = varVariantByRef then
        result := VarIsVoid(PVariant(VPointer)^)
      else if (vt = varStringByRef) or
              (vt = varOleStrByRef)
              {$ifdef HASVARUSTRING} or
              (vt = varUStringByRef)
              {$endif HASVARUSTRING} then
        result := PPointer(VAny)^ = nil
      else if vt = DocVariantVType then
        result := TDocVariantData(V).Count = 0
      else
      begin
        custom := FindSynVariantType(vt);
        result := (custom <> nil) and
                  custom.IsVoid(TVarData(V)); // e.g. TBsonVariant.IsVoid
      end;
    end;
end;

function VarStringOrNull(const v: RawUtf8): variant;
begin
  if v = '' then
    SetVariantNull(result{%H-})
  else
    RawUtf8ToVariant(v, result);
end;

procedure SetVariantByRef(const Source: Variant; var Dest: Variant);
var
  vt: cardinal;
begin
  if PInteger(@Dest)^ <> 0 then // VarClear() is not always inlined :(  （VarClear() 并不总是内联:(）
    VarClear(Dest);
  vt := TVarData(Source).VType;
  if ((vt and varByRef) <> 0) or
     (vt in VTYPE_SIMPLE) then
    TVarData(Dest) := TVarData(Source)
  else if not SetVariantUnRefSimpleValue(Source, TVarData(Dest)) then
  begin
    TRttiVarData(Dest).VType := varVariantByRef;
    TVarData(Dest).VPointer := @Source;
  end;
end;

procedure SetVariantByValue(const Source: Variant; var Dest: Variant);
var
  s: PVarData;
  d: TVarData absolute Dest;
  dt: cardinal absolute Dest;
  vt: cardinal;
  ct: TSynInvokeableVariantType;
begin
  s := @Source;
  if PInteger(@Dest)^ <> 0 then // VarClear() is not always inlined :(  （VarClear() 并不总是内联:(）
    VarClear(Dest);
  vt := s^.VType;
  while vt = varVariantByRef do
  begin
    s := s^.VPointer;
    vt := s^.VType;
  end;
  case vt of
    varEmpty..varDate,
    varBoolean,
    varShortInt..varWord64:
      begin
        dt := vt;
        d.VInt64 := s^.VInt64;
      end;
    varString:
      begin
        dt := varString;
        d.VAny := nil;
        RawByteString(d.VAny) := RawByteString(s^.VAny);
      end;
    varStringByRef:
      begin
        dt := varString;
        d.VAny := nil;
        RawByteString(d.VAny) := PRawByteString(s^.VAny)^;
      end;
    {$ifdef HASVARUSTRING}
    varUString,
    varUStringByRef,
    {$endif HASVARUSTRING}
    varOleStr,
    varOleStrByRef:
      begin
        dt := varString;
        d.VAny := nil;
        VariantToUtf8(PVariant(s)^, RawUtf8(d.VAny)); // store as RawUtf8
      end;
  else // note: varVariant should not happen here
    if DocVariantType.FindSynVariantType(vt, ct) then
      ct.CopyByValue(d, s^) // needed e.g. for TBsonVariant
    else
      SetVariantUnRefSimpleValue(PVariant(s)^, d);
  end;
end;

procedure ZeroFill(Value: PVarData);
begin
  // slightly faster than FillChar(Value,SizeOf(Value),0);
  PInt64Array(Value)^[0] := 0;
  PInt64Array(Value)^[1] := 0;
  {$ifdef CPU64}
  PInt64Array(Value)^[2] := 0;
  {$endif CPU64}
end;

procedure FillZero(var value: variant);
begin
  if TVarData(value).VType = varString then
    FillZero(RawByteString(TVarData(value).VAny));
  VarClear(value);
end;

procedure _VariantClearSeveral(V: PVarData; n: integer);
var
  vt, docv: cardinal;
  handler: TCustomVariantType;
  clearproc: procedure(V: PVarData);
label
  clr, hdr;
begin
  handler := nil;
  docv := DocVariantVType;
  clearproc := @VarClearProc;
  repeat
    vt := V^.VType;
    if vt <= varWord64 then
    begin
      if (vt >= varOleStr) and
         (vt <= varError) then
        if vt = varOleStr then
          WideString(V^.VAny) := ''
        else
          goto clr; // varError/varDispatch
    end // note: varVariant/varUnknown are not handled because should not appear  （注意：varVariant/varUnknown 不被处理，因为不应该出现）
    else if vt = varString then
      {$ifdef FPC}
      FastAssignNew(V^.VAny)
      {$else}
      RawUtf8(V^.VAny) := ''
      {$endif FPC}
    else if vt < varByRef then // varByRef has no refcount -> nothing to clear
      if vt = docv then
        PDocVariantData(V)^.ClearFast // faster than Clear
      {$ifdef HASVARUSTRING}
      else if vt = varUString then
        UnicodeString(V^.VAny) := ''
      {$endif HASVARUSTRING}
      else if vt >= varArray then // custom types are below varArray
clr:    clearproc(V)
      else if handler = nil then
        if FindCustomVariantType(vt, handler) then
hdr:      handler.Clear(V^)
        else
          goto clr
      else if vt = handler.VarType then
        goto hdr
      else
        goto clr;
    PInteger(V)^ := varEmpty; // reset VType
    inc(V);
    dec(n);
  until n = 0;
end;

procedure RawUtf8ToVariant(const Txt: RawUtf8; var Value: TVarData;
  ExpectedValueType: cardinal);
begin
  if ExpectedValueType = varString then
  begin
    RawUtf8ToVariant(Txt, variant(Value));
    exit;
  end;
  VarClearAndSetType(variant(Value), ExpectedValueType);
  Value.VAny := nil; // avoid GPF below
  if Txt <> '' then
    case ExpectedValueType of
      varOleStr:
        Utf8ToWideString(Txt, WideString(Value.VAny));
      {$ifdef HASVARUSTRING}
      varUString:
        Utf8DecodeToUnicodeString(
          pointer(Txt), length(Txt), UnicodeString(Value.VAny));
      {$endif HASVARUSTRING}
    else
      raise ESynVariant.CreateUtf8('RawUtf8ToVariant(%)?', [ExpectedValueType]);
    end;
end;

function VariantToString(const V: Variant): string;
var
  wasString: boolean;
  tmp: RawUtf8;
  vt: cardinal;
begin
  vt := TVarData(V).VType;
  case vt of
    varEmpty,
    varNull:
      result := ''; // default VariantToUtf8(null)='null'
    {$ifdef UNICODE} // not HASVARUSTRING: here we handle string=UnicodeString
    varUString:
      result := UnicodeString(TVarData(V).VAny);
  else
    if vt = varUStringByRef then
      result := PUnicodeString(TVarData(V).VAny)^
    {$endif UNICODE}
    else
    begin
      VariantToUtf8(V, tmp, wasString);
      if tmp = '' then
        result := ''
      else
        Utf8ToStringVar(tmp, result);
    end;
  end;
end;

procedure VariantToVarRec(const V: variant; var result: TVarRec);
begin
  result.VType := vtVariant;
  if TVarData(V).VType = varVariantByRef then
    result.VVariant := TVarData(V).VPointer
  else
    result.VVariant := @V;
end;

procedure VariantsToArrayOfConst(const V: array of variant; VCount: PtrInt;
  out result: TTVarRecDynArray);
var
  i: PtrInt;
begin
  SetLength(result, VCount);
  for i := 0 to VCount - 1 do
    VariantToVarRec(V[i], result[i]);
end;

function VariantsToArrayOfConst(const V: array of variant): TTVarRecDynArray;
begin
  VariantsToArrayOfConst(V, length(V), result);
end;

function RawUtf8DynArrayToArrayOfConst(const V: array of RawUtf8): TTVarRecDynArray;
var
  i: PtrInt;
begin
  result := nil;
  SetLength(result, Length(V));
  for i := 0 to Length(V) - 1 do
  begin
    result[i].VType := vtAnsiString;
    result[i].VAnsiString := pointer(V[i]);
  end;
end;

function VarRecToVariant(const V: TVarRec): variant;
begin
  VarRecToVariant(V, result);
end;

procedure VarRecToVariant(const V: TVarRec; var result: variant);
begin
  VarClear(result{%H-});
  with TVarData(result) do
    case V.VType of
      vtPointer:
        VType := varNull;
      vtBoolean:
        begin
          VType := varBoolean;
          VBoolean := V.VBoolean;
        end;
      vtInteger:
        begin
          VType := varInteger;
          VInteger := V.VInteger;
        end;
      vtInt64:
        begin
          VType := varInt64;
          VInt64 := V.VInt64^;
        end;
      {$ifdef FPC}
      vtQWord:
        begin
          VType := varWord64;
          VQWord := V.VQWord^;
        end;
      {$endif FPC}
      vtCurrency:
        begin
          VType := varCurrency;
          VInt64 := PInt64(V.VCurrency)^;
        end;
      vtExtended:
        begin
          VType := varDouble;
          VDouble := V.VExtended^;
        end;
      vtVariant:
        result := V.VVariant^;
      // warning: use varStringByRef makes GPF -> safe and fast refcount
      vtAnsiString:
        begin
          VType := varString;
          VAny := nil;
          RawByteString(VAny) := RawByteString(V.VAnsiString);
        end;
      {$ifdef HASVARUSTRING}
      vtUnicodeString,
      {$endif HASVARUSTRING}
      vtWideString,
      vtString,
      vtPChar,
      vtChar,
      vtWideChar,
      vtClass:
        begin
          VType := varString;
          VString := nil; // avoid GPF on next line
          VarRecToUtf8(V, RawUtf8(VString)); // return as new RawUtf8 instance
        end;
      vtObject:
        // class instance will be serialized as a TDocVariant
        ObjectToVariant(V.VObject, result, [woDontStoreDefault]);
    else
      raise ESynVariant.CreateUtf8('Unhandled TVarRec.VType=%', [V.VType]);
    end;
end;

function VariantDynArrayToJson(const V: TVariantDynArray): RawUtf8;
var
  tmp: TDocVariantData;
begin
  tmp.InitArrayFromVariants(V);
  result := tmp.ToJson;
end;

function VariantDynArrayToRawUtf8DynArray(const V: TVariantDynArray): TRawUtf8DynArray;
var
  i: PtrInt;
  ws: boolean;
begin
  result := nil;
  if V = nil then
    exit;
  SetLength(result, length(V));
  for i := 0 to length(V) - 1 do
    VariantToUtf8(V[i], result[i], ws);
end;

function JsonToVariantDynArray(const Json: RawUtf8): TVariantDynArray;
var
  tmp: TDocVariantData;
begin
  tmp.InitJson(Json, JSON_FAST);
  result := tmp.VValue;
end;

function ValuesToVariantDynArray(const items: array of const): TVariantDynArray;
var
  tmp: TDocVariantData;
begin
  tmp.InitArray(items, JSON_FAST);
  result := tmp.VValue;
end;


function SortDynArrayEmptyNull(const A, B): integer;
begin
  result := 0; // VType=varEmpty/varNull are always equal
end;

function SortDynArrayWordBoolean(const A, B): integer;
begin
  if WordBool(A) then // normalize
    if WordBool(B) then
      result := 0
    else
      result := 1
  else if WordBool(B) then
    result := -1
  else
    result := 0;
end;

var
  _CMP2SORT: array[0..18] of TDynArraySortCompare = (
    nil,                         // 0
    SortDynArrayEmptyNull,       // 1
    SortDynArraySmallInt,        // 2
    SortDynArrayInteger,         // 3
    SortDynArraySingle,          // 4
    SortDynArrayDouble,          // 5
    SortDynArrayInt64,           // 6
    SortDynArrayDouble,          // 7
    SortDynArrayShortInt,        // 8
    SortDynArrayByte,            // 9
    SortDynArrayWord,            // 10
    SortDynArrayCardinal,        // 11
    SortDynArrayInt64,           // 12
    SortDynArrayQWord,           // 13
    SortDynArrayWordBoolean,     // 14
    {$ifdef CPUINTEL}
    SortDynArrayAnsiString,      // 15
    {$else}
    SortDynArrayRawByteString,
    {$endif CPUINTEL}
    SortDynArrayAnsiStringI,     // 16
    SortDynArrayUnicodeString,   // 17
    SortDynArrayUnicodeStringI); // 18

  // FastVarDataComp() efficient lookup for per-VType comparison function
  _VARDATACMP: array[0 .. $102 {varUString}, boolean] of byte; // _CMP2SORT[]

function FastVarDataComp(A, B: PVarData; caseInsensitive: boolean): integer;
var
  at, bt, sametypecomp: PtrUInt;
  au, bu: pointer;
  wasString: boolean;
label
  rtl, utf;
begin
  if A <> nil then
    repeat
      at := cardinal(A^.VType);
      if at <> varVariantByRef then
        break;
      A := A^.VPointer;
    until false
  else
    at := varNull;
  if B <> nil then
    repeat
      bt := cardinal(B^.VType);
      if bt <> varVariantByRef then
        break;
      B := B^.VPointer;
    until false
  else
    bt := varNull;
  if at = bt then
    // optimized comparison if A and B share the same type (most common case)
    if at <= high(_VARDATACMP) then
    begin
      sametypecomp := _VARDATACMP[at, caseInsensitive];
      if sametypecomp <> 0 then
        result := _CMP2SORT[sametypecomp](A^.VAny, B^.VAny)
      else
rtl:    result := VariantCompSimple(PVariant(A)^, PVariant(B)^)
    end
    else if at = varStringByRef then
      // e.g. from TRttiVarData / TRttiCustomProp.CompareValue
      result := _CMP2SORT[_VARDATACMP[varString, caseInsensitive]](
        PPointer(A^.VAny)^, PPointer(B^.VAny)^)
    else if at = varSynUnicode or varByRef then
      result := _CMP2SORT[_VARDATACMP[varSynUnicode, caseInsensitive]](
         PPointer(A^.VAny)^, PPointer(B^.VAny)^)
    else if at < varFirstCustom then
      goto rtl
    else if at = DocVariantVType then
      // direct TDocVariantDat.VName/VValue comparison with no serialization
      result := PDocVariantData(A)^.Compare(PDocVariantData(B)^, caseInsensitive)
    else
      // compare from custom types UTF-8 text representation/serialization
      begin
utf:    au := nil; // no try..finally for local RawUtf8 variables
        bu := nil;
        VariantToUtf8(PVariant(A)^, RawUtf8(au), wasString);
        VariantToUtf8(PVariant(B)^, RawUtf8(bu), wasString);
        result := SortDynArrayAnsiStringByCase[caseInsensitive](au, bu);
        FastAssignNew(au);
        FastAssignNew(bu);
      end
  // A and B do not share the same type
  else if (at <= varNull) or
          (bt <= varNull) then
    result := ord(at > varNull) - ord(bt > varNull)
  else if (at < varString) and
          (at <> varOleStr) and
          (bt < varString) and
          (bt <> varOleStr) then
    goto rtl
  else
    goto utf;
end;

function VariantCompare(const V1, V2: variant): PtrInt;
begin
  result := FastVarDataComp(@V1, @V2, {caseins=}false);
end;

function VariantCompareI(const V1, V2: variant): PtrInt;
begin
  result := FastVarDataComp(@V1, @V2, {caseins=}true);
end;

function VariantEquals(const V: Variant; const Str: RawUtf8;
  CaseSensitive: boolean): boolean;

  function Complex: boolean;
  var
    wasString: boolean;
    tmp: RawUtf8;
  begin
    VariantToUtf8(V, tmp, wasString);
    if CaseSensitive then
      result := (tmp = Str)
    else
      result := PropNameEquals(tmp, Str);
  end;

var
  v1, v2: Int64;
  vt: cardinal;
begin
  vt := TVarData(V).VType;
  with TVarData(V) do
    case vt of
      varEmpty,
      varNull:
        result := Str = '';
      varBoolean:
        result := VBoolean = (Str <> '');
      varString:
        if CaseSensitive then
          result := RawUtf8(VString) = Str
        else
          result := PropNameEquals(RawUtf8(VString), Str);
    else
      if VariantToInt64(V, v1) then
      begin
        SetInt64(pointer(Str), v2);
        result := v1 = v2;
      end
      else
        result := Complex;
    end;
end;


{ ************** Custom Variant Types with JSON support }

var
  SynVariantTypesSafe: TLightLock; // protects only SynRegisterCustomVariantType

  /// list of custom types (but not DocVariantVType) supporting TryJsonToVariant
  SynVariantTryJsonTypes: array of TSynInvokeableVariantType;

function FindSynVariantType(aVarType: cardinal): TSynInvokeableVariantType;
var
  n: integer;
  t: ^TSynInvokeableVariantType;
begin
  if (aVarType >= varFirstCustom) and
     (aVarType < varArray) then
  begin
    t := pointer(SynVariantTypes);
    n := PDALen(PAnsiChar(t) - _DALEN)^ + _DAOFF;
    repeat
      result := t^;
      if result.VarType = aVarType then
        exit;
      inc(t);
      dec(n);
    until n = 0;
  end;
  result := nil;
end;

function SynRegisterCustomVariantType(
  aClass: TSynInvokeableVariantTypeClass): TSynInvokeableVariantType;
var
  i: PtrInt;
begin
  SynVariantTypesSafe.Lock;
  try
    for i := 0 to length(SynVariantTypes) - 1 do
    begin
      result := SynVariantTypes[i];
      if PPointer(result)^ = pointer(aClass) then
        // returns already registered instance
        exit;
    end;
    result := aClass.Create; // register variant type
    ObjArrayAdd(SynVariantTypes, result);
    if sioHasTryJsonToVariant in result.Options then
      ObjArrayAdd(SynVariantTryJsonTypes, result);
  finally
    SynVariantTypesSafe.UnLock;
  end;
end;


{ TSynInvokeableVariantType }

constructor TSynInvokeableVariantType.Create;
begin
  inherited Create; // call RegisterCustomVariantType(self)
end;

function TSynInvokeableVariantType.IterateCount(const V: TVarData;
  GetObjectAsValues: boolean): integer;
begin
  result := -1; // this is not an array
end;

procedure TSynInvokeableVariantType.Iterate(var Dest: TVarData;
  const V: TVarData; Index: integer);
begin
  // do nothing
end;

{$ifdef ISDELPHI}
function TSynInvokeableVariantType.FixupIdent(const AText: string): string;
begin
  result := AText; // NO uppercased identifier for our custom types!
end;
{$endif ISDELPHI}

function TSynInvokeableVariantType.{%H-}IntGet(var Dest: TVarData;
  const Instance: TVarData; Name: PAnsiChar; NameLen: PtrInt;
  NoException: boolean): boolean;
begin
  raise ESynVariant.CreateUtf8('Unexpected %.IntGet(%): this kind of ' +
    'custom variant does not support sub-fields', [self, Name]);
end;

function TSynInvokeableVariantType.{%H-}IntSet(const Instance, Value: TVarData;
  Name: PAnsiChar; NameLen: PtrInt): boolean;
begin
  raise ESynVariant.CreateUtf8('Unexpected %.IntSet(%): this kind of ' +
    'custom variant is read-only', [self, Name]);
end;

const
  DISPATCH_METHOD = 1;
  DISPATCH_PROPERTYGET = 2; // in practice, never generated by the FPC compiler
  DISPATCH_PROPERTYPUT = 4;
  ARGTYPE_MASK = $7f;
  ARGREF_MASK = $80;
  VAR_PARAMNOTFOUND = HRESULT($80020004);

{$ifdef FPC}
var
  DispInvokeArgOrderInverted: boolean; // circumvent FPC 3.2+ breaking change
{$endif FPC}

{$ifdef FPC_VARIANTSETVAR}
procedure TSynInvokeableVariantType.DispInvoke(
  Dest: PVarData; var Source: TVarData; CallDesc: PCallDesc; Params: Pointer);
{$else} // see http://mantis.freepascal.org/view.php?id=26773
  {$ifdef ISDELPHIXE7}
procedure TSynInvokeableVariantType.DispInvoke(
  Dest: PVarData; [ref] const Source: TVarData; // why not just "var" ????
  CallDesc: PCallDesc; Params: Pointer);
  {$else}
procedure TSynInvokeableVariantType.DispInvoke(
  Dest: PVarData; const Source: TVarData; CallDesc: PCallDesc; Params: Pointer);
  {$endif ISDELPHIXE7}
{$endif FPC_VARIANTSETVAR}
var
  name: string;
  res: TVarData;
  namelen, i, t, n: PtrInt;
  nameptr, a: PAnsiChar;
  asize: PtrInt;
  v: PVarData;
  args: TVarDataArray; // DoProcedure/DoFunction require a dynamic array
  {$ifdef FPC}
  inverted: boolean;
  {$endif FPC}

  procedure RaiseInvalid;
  begin
    raise ESynVariant.CreateUtf8('%.DispInvoke: invalid %(%) call',
      [self, name, CallDesc^.ArgCount]);
  end;

begin
  // circumvent https://bugs.freepascal.org/view.php?id=38653 and
  // inverted args order FPC bugs, avoid unneeded conversion to varOleString
  // for Delphi, and implement direct IntGet/IntSet calls for all
  n := CallDesc^.ArgCount;
  nameptr := @CallDesc^.ArgTypes[n];
  namelen := StrLen(nameptr);
  // faster direct property getter
  if (Dest <> nil) and
     (n = 0) and
     (CallDesc^.CallType in [DISPATCH_METHOD, DISPATCH_PROPERTYGET]) and
     IntGet(Dest^, Source, nameptr, namelen, {noexception=}false) then
    exit;
  Ansi7ToString(pointer(nameptr), namelen, name);
  if n > 0 then
  begin
    // convert varargs Params buffer into an array of TVarData
    SetLength(args, n);
    {$ifdef FPC} // circumvent FPC 3.2+ inverted order
    inverted := (n > 1) and
                DispInvokeArgOrderInverted;
    if inverted then
      v := @args[n - 1]
    else
    {$endif FPC}
      v := pointer(args);
    a := Params;
    for i := 0 to n - 1 do
    begin
      asize := SizeOf(pointer);
      t := CallDesc^.ArgTypes[i] and ARGTYPE_MASK;
      case t of
        {$ifdef HASVARUSTRARG}
        varUStrArg:
          t := varUString;
        {$endif HASVARUSTRARG}
        varStrArg:
          t := varString;
      end;
      if CallDesc^.ArgTypes[i] and ARGREF_MASK <> 0 then
      begin
        TRttiVarData(v^).VType := t or varByRef;
        v^.VPointer := PPointer(a)^;
      end
      else
      begin
        TRttiVarData(v^).VType := t;
        case t of
          varError:
            begin
              v^.VError := VAR_PARAMNOTFOUND;
              asize := 0;
            end;
          varVariant:
            {$ifdef CPU32DELPHI}
            begin
              v^ := PVarData(a)^;
              asize := SizeOf(TVarData); // pushed by value
            end;
            {$else}
            v^ := PPVarData(a)^^; // pushed by reference (as other parameters)
            {$endif CPU32DELPHI}
          varDouble,
          varCurrency,
          varDate,
          varInt64,
          varWord64:
            begin
              v^.VInt64 := PInt64(a)^;
              asize := SizeOf(Int64);
            end;
          // small values are stored as pointers on stack but pushed as 32-bit
          varSingle,
          varSmallint,
          varInteger,
          varLongWord,
          varBoolean,
          varShortInt,
          varByte,
          varWord:
            v^.VInteger := PInteger(a)^; // we assume little endian
        else
          v^.VAny := PPointer(a)^; // e.g. varString or varOleStr
        end;
      end;
      inc(a, asize);
      {$ifdef FPC}
      if inverted then
        dec(v)
      else
      {$endif FPC}
        inc(v);
    end;
  end;
  case CallDesc^.CallType of
    // note: IntGet was already tried in function trailer
    DISPATCH_METHOD:
      if Dest <> nil then
      begin
        if not DoFunction(Dest^, Source, name, args) then
          RaiseInvalid;
      end
      else if not DoProcedure(Source, name, args) then
      begin
        PCardinal(@res)^ := varEmpty;
        try
          if not DoFunction(Dest^, Source, name, args) then
            RaiseInvalid;
        finally
          VarClearProc(res);
        end;
      end;
    DISPATCH_PROPERTYGET:
      if (Dest = nil) or
         not DoFunction(Dest^, Source, name, args) then
        RaiseInvalid;
    DISPATCH_PROPERTYPUT:
      if (Dest <> nil) or
         (n <> 1) or
         not IntSet(Source, args[0], nameptr, namelen) then
        RaiseInvalid;
  else
    RaiseInvalid;
  end;
end;

procedure TSynInvokeableVariantType.Clear(var V: TVarData);
begin
  ZeroFill(@V); // will set V.VType := varEmpty
end;

procedure TSynInvokeableVariantType.Copy(var Dest: TVarData;
  const Source: TVarData; const Indirect: boolean);
begin
  if Indirect then
    SetVariantByRef(variant(Source), variant(Dest))
  else
  begin
    VarClear(variant(Dest)); // Dest may be a complex type
    Dest := Source;
  end;
end;

procedure TSynInvokeableVariantType.CopyByValue(
  var Dest: TVarData; const Source: TVarData);
begin
  Copy(Dest, Source, {Indirect=} false);
end;

function TSynInvokeableVariantType.TryJsonToVariant(var Json: PUtf8Char;
  var Value: variant; EndOfObject: PUtf8Char): boolean;
begin
  result := false;
end;

procedure TSynInvokeableVariantType.ToJson(W: TJsonWriter; Value: PVarData);
begin
  raise ESynVariant.CreateUtf8('%.ToJson is not implemented', [self]);
end;

procedure TSynInvokeableVariantType.ToJson(Value: PVarData;
  var Json: RawUtf8; const Prefix, Suffix: RawUtf8; Format: TTextWriterJsonFormat);
var
  W: TJsonWriter;
  temp: TTextWriterStackBuffer;
begin
  W := TJsonWriter.CreateOwnedStream(temp);
  try
    if Prefix <> '' then
      W.AddString(Prefix);
    ToJson(W, Value); // direct TSynInvokeableVariantType serialization
    if Suffix <> '' then
      W.AddString(Suffix);
    W.SetText(Json, Format);
  finally
    W.Free;
  end;
end;

function TSynInvokeableVariantType.IsOfType(const V: variant): boolean;
var
  vt: cardinal;
  vd: PVarData;
{%H-}begin
  if self <> nil then
  begin
    vd := @V;
    repeat
      vt := vd^.VType;
      if vt <> varVariantByRef then
        break;
      vd := vd^.VPointer;
    until false;
    result := vt = VarType;
  end
  else
    result := false;
end;

function TSynInvokeableVariantType.IsVoid(const V: TVarData): boolean;
begin
  result := false; // not void by default
end;

function TSynInvokeableVariantType.FindSynVariantType(aVarType: cardinal;
  out CustomType: TSynInvokeableVariantType): boolean;
var
  ct: TSynInvokeableVariantType;
begin
  if (self <> nil) and
     (aVarType = VarType) then
    ct := self
  else
    ct := mormot.core.variants.FindSynVariantType(aVarType);
  CustomType := ct;
  result := ct <> nil;
end;

function TSynInvokeableVariantType.FindSynVariantType(
  aVarType: cardinal): TSynInvokeableVariantType;
begin
  if aVarType = VarType then
    result := self
  else
    result := mormot.core.variants.FindSynVariantType(aVarType);
end;

procedure TSynInvokeableVariantType.Lookup(var Dest: TVarData;
  const Instance: TVarData; FullName: PUtf8Char; PathDelim: AnsiChar);
var
  handler: TSynInvokeableVariantType;
  v, tmp: TVarData; // PVarData wouldn't store e.g. RowID/count
  vt: cardinal;
  n: ShortString;
begin
  TRttiVarData(Dest).VType := varEmpty; // left to Unassigned if not found
  v := Instance;
  repeat
    vt := v.VType;
    if vt <> varVariantByRef then
      break;
    v := PVarData(v.VPointer)^;
  until false;
  repeat
    if vt < varFirstCustom then
      exit; // we need a complex type to lookup
    GetNextItemShortString(FullName, @n, PathDelim); // n ends with #0
    if n[0] in [#0, #254] then
      exit;
    if vt = VarType then
      handler := self
    else
    begin
      handler := mormot.core.variants.FindSynVariantType(vt);
      if handler = nil then
        exit;
    end;
    tmp := v; // v will be modified in-place
    TRttiVarData(v).VType := varEmpty; // IntGet() would clear it otherwise!
    if not handler.IntGet(v, tmp, @n[1], ord(n[0]), {noexc=}true) then
      exit; // property not found (no exception should be raised in Lookup)
    repeat
      vt := v.VType;
      if vt <> varVariantByRef then
        break;
      v := PVarData(v.VPointer)^;
    until false;
    if (vt = DocVariantVType) and
       (TDocVariantData(v).VCount = 0) then
      // recognize void TDocVariant as null
      v.VType := varNull; // do not use PCardinal/TRttiVarData(v).VType here
  until FullName = nil;
  Dest := v;
end;

function CustomVariantToJson(W: TJsonWriter; Value: PVarData;
  Escape: TTextWriterKind): boolean;
var
  v: TCustomVariantType;
  tmp: variant;
begin
  result := true;
  if FindCustomVariantType(Value.VType, v) then
    if v.InheritsFrom(TSynInvokeableVariantType) then
      TSynInvokeableVariantType(v).ToJson(W, Value)
    else
      try
        v.CastTo(TVarData(tmp), Value^, varNativeString);
        W.AddVariant(tmp, Escape);
      except
        result := false;
      end
  else
    result := false;
end;


function ToText(kind: TDocVariantKind): PShortString;
begin
  result := GetEnumName(TypeInfo(TDocVariantKind), ord(kind));
end;

procedure NeedJsonEscape(const Value: variant; var Json: RawUtf8;
  Escape: TTextWriterKind);
var
  temp: TTextWriterStackBuffer;
begin
  with TJsonWriter.CreateOwnedStream(temp) do
    try
      AddVariant(Value, Escape); // will use mormot.core.json serialization
      SetText(Json, jsonCompact);
    finally
      Free;
    end;
end;

procedure __VariantSaveJson(V: PVarData; Escape: TTextWriterKind;
  var result: RawUtf8);
var
  cv: TSynInvokeableVariantType;
  vt: cardinal;
  dummy: boolean;
begin
  // is likely to be called from AddVariant() but can be used for simple values
  if cardinal(V.VType) = varVariantByRef then
    V := V^.VPointer;
  cv := FindSynVariantType(V.VType);
  if cv = nil then
  begin
    vt := V.VType;
    if (vt >= varFirstCustom) or
       ((Escape <> twNone) and
        not (vt in [varEmpty..varDate, varBoolean, varShortInt..varWord64])) then
      NeedJsonEscape(PVariant(V)^, result, Escape)
    else
      VariantToUtf8(PVariant(V)^, result, dummy); // no escape for simple values
  end
  else
    cv.ToJson(V, result);
end;


{ EDocVariant }

class procedure EDocVariant.RaiseSafe(Kind: TDocVariantKind);
begin
  raise CreateUtf8('_Safe(%)?', [ToText(Kind)^]);
end;


// defined here for proper inlining
// PInteger() is faster than (dvoXXX in VOptions) especially on Intel CPUs

function TDocVariantData.GetKind: TDocVariantKind;
var
  c: cardinal;
begin
  c := PInteger(@self)^;
  if (c and (1 shl (ord(dvoIsObject) + 16))) <> 0 then
    result := dvObject
  else if (c and (1 shl (ord(dvoIsArray) + 16))) <> 0 then
    result := dvArray
  else
    result := dvUndefined;
end;

function TDocVariantData.IsObject: boolean;
begin
  result := (PInteger(@self)^ and (1 shl (ord(dvoIsObject) + 16))) <> 0;
end;

function TDocVariantData.IsArray: boolean;
begin
  result := (PInteger(@self)^ and (1 shl (ord(dvoIsArray) + 16))) <> 0;
end;

function TDocVariantData.IsCaseSensitive: boolean;
begin
  result := (PInteger(@self)^ and (1 shl (ord(dvoNameCaseSensitive) + 16))) <> 0;
end;


{ TDocVariant }

destructor TDocVariant.Destroy;
begin
  inherited Destroy;
  fInternNames.Free;
  fInternValues.Free;
end;

const
  _GETMETHOD: array[0..3] of PAnsiChar = (
    'COUNT', // 0
    'KIND',  // 1
    'JSON',  // 2
    nil);

function IntGetPseudoProp(ndx: PtrInt; const source: TDocVariantData;
  var Dest: variant): boolean;
begin
  // sub-function to avoid temporary RawUtf8 for source.ToJson
  result := true;
  case ndx of
    0:
      Dest := source.Count;
    1:
      Dest := ord(source.GetKind);
    2:
      RawUtf8ToVariant(source.ToJson, Dest);
  else
    result := false;
  end;
end;

function TDocVariant.IntGet(var Dest: TVarData; const Instance: TVarData;
  Name: PAnsiChar; NameLen: PtrInt; NoException: boolean): boolean;
var
  dv: TDocVariantData absolute Instance;
  ndx: integer;
begin
  if Name = nil then
    result := false
  else if (NameLen > 4) and
          (Name[0] = '_') and
          IntGetPseudoProp(IdemPPChar(@Name[1], @_GETMETHOD), dv, variant(Dest)) then
    result := true
  else
  begin
    ndx := dv.GetValueIndex(pointer(Name), NameLen, dv.IsCaseSensitive);
    if ndx < 0 then
      if NoException or
         (dvoReturnNullForUnknownProperty in dv.VOptions) then
      begin
        SetVariantNull(PVariant(@Dest)^);
        result := false;
      end
      else
        raise EDocVariant.CreateUtf8('[%] property not found', [Name])
    else
    begin
      SetVariantByRef(dv.VValue[ndx], PVariant(@Dest)^);
      result := true;
    end;
  end;
end;

function TDocVariant.IntSet(const Instance, Value: TVarData;
  Name: PAnsiChar; NameLen: PtrInt): boolean;
var
  ndx: PtrInt;
  dv: TDocVariantData absolute Instance;
begin
  result := true;
  if dv.IsArray and
     (PWord(Name)^ = ord('_')) then
  begin
    dv.AddItem(variant(Value));
    exit;
  end;
  ndx := dv.GetValueIndex(pointer(Name), NameLen, dv.IsCaseSensitive);
  if ndx < 0 then
    ndx := dv.InternalAdd(Name, NameLen);
  dv.InternalSetValue(ndx, variant(Value));
end;

function TDocVariant.IterateCount(const V: TVarData;
  GetObjectAsValues: boolean): integer;
var
  Data: TDocVariantData absolute V;
begin
  if Data.IsArray or
     (GetObjectAsValues and
      Data.IsObject) then
    result := Data.VCount
  else
    result := -1;
end;

procedure TDocVariant.Iterate(var Dest: TVarData;
  const V: TVarData; Index: integer);
var
  Data: TDocVariantData absolute V;
begin // note: IterateCount() may accept IsObject values[]
  if cardinal(Index) < cardinal(Data.VCount) then
    Dest := TVarData(Data.VValue[Index])
  else
    TRttiVarData(Dest).VType := varEmpty;
end;

function TDocVariant.IsVoid(const V: TVarData): boolean;
begin
  result := TDocVariantData(V).Count > 0;
end;

function TDocVariant.DoProcedure(const V: TVarData; const Name: string;
  const Arguments: TVarDataArray): boolean;
var
  Data: PDocVariantData;
begin
  result := false;
  Data := @V; // allow to modify a const argument
  case length(Arguments) of
    0:
      if SameText(Name, 'Clear') then
      begin
        Data^.VCount := 0;
        Data^.VOptions := Data^.VOptions - [dvoIsObject, dvoIsArray];
        result := true;
      end;
    1:
      if SameText(Name, 'Add') then
      begin
        Data^.AddItem(variant(Arguments[0]));
        result := true;
      end
      else if SameText(Name, 'Delete') then
      begin
        Data^.Delete(Data^.GetValueIndex(ToUtf8(Arguments[0])));
        result := true;
      end;
    2:
      if SameText(Name, 'Add') then
      begin
        Data^.AddValue(ToUtf8(Arguments[0]), variant(Arguments[1]));
        result := true;
      end;
  end;
end;

function TDocVariant.DoFunction(var Dest: TVarData; const V: TVarData;
  const Name: string; const Arguments: TVarDataArray): boolean;
var
  ndx: integer;
  Data: PDocVariantData;
  temp: RawUtf8;
begin
  result := true;
  Data := @V; // allow to modify a const argument
  case length(Arguments) of
    1:
      if SameText(Name, 'Exists') then
      begin
        variant(Dest) := Data.GetValueIndex(ToUtf8(Arguments[0])) >= 0;
        exit;
      end
      else if SameText(Name, 'NameIndex') then
      begin
        variant(Dest) := Data.GetValueIndex(ToUtf8(Arguments[0]));
        exit;
      end
      else if VariantToInteger(variant(Arguments[0]), ndx) then
      begin
        if (Name = '_') or
           SameText(Name, 'Value') then
        begin
          Data.RetrieveValueOrRaiseException(ndx, variant(Dest), true);
          exit;
        end
        else if SameText(Name, 'Name') then
        begin
          Data.RetrieveNameOrRaiseException(ndx, temp);
          RawUtf8ToVariant(temp, variant(Dest));
          exit;
        end;
      end
      else if (Name = '_') or
              SameText(Name, 'Value') then
      begin
        temp := ToUtf8(Arguments[0]);
        Data.RetrieveValueOrRaiseException(pointer(temp), length(temp),
          Data.IsCaseSensitive, variant(Dest), true);
        exit;
      end;
  end;
  result := dvoReturnNullForUnknownProperty in Data.VOptions; // to avoid error
end;

procedure TDocVariant.ToJson(W: TJsonWriter; Value: PVarData);
var
  forced: TTextWriterOptions;
  nam: PPUtf8Char;
  val: PVariant;
  n: integer;
  checkExtendedPropName: boolean;
begin
  if cardinal(Value.VType) = varVariantByRef then // inlined Safe()^
    Value := Value.VPointer;
  if cardinal(Value.VType) <> DocVariantVType then
    W.AddNull
  else
  begin
    forced := [];
    if [twoForceJsonExtended, twoForceJsonStandard] * W.CustomOptions = [] then
    begin
      if dvoSerializeAsExtendedJson in PDocVariantData(Value)^.VOptions then
        forced := [twoForceJsonExtended]
      else
        forced := [twoForceJsonStandard];
      W.CustomOptions := W.CustomOptions + forced;
    end;
    n := PDocVariantData(Value)^.VCount;
    val := pointer(PDocVariantData(Value)^.VValue);
    if PDocVariantData(Value)^.IsObject then
    begin
      checkExtendedPropName := twoForceJsonExtended in W.CustomOptions;
      W.Add('{');
      nam := pointer(PDocVariantData(Value)^.VName);
      if n <> 0 then
        repeat
          if checkExtendedPropName and
             JsonPropNameValid(nam^) then
            W.AddNoJsonEscape(nam^, PStrLen(nam^ - _STRLEN)^)
          else
          begin
            W.Add('"');
            W.AddJsonEscape(nam^);
            W.Add('"');
          end;
          W.Add(':');
          W.AddVariant(val^, twJsonEscape);
          dec(n);
          if n = 0 then
            break;
          W.AddComma;
          inc(nam);
          inc(val);
        until false;
      W.Add('}');
    end
    else if PDocVariantData(Value)^.IsArray then
    begin
      W.Add('[');
      if n <> 0 then      
        repeat
          W.AddVariant(val^, twJsonEscape);
          dec(n);
          if n = 0 then
            break;
          W.AddComma;
          inc(val);
        until false;
      W.Add(']');
    end
    else
      W.AddNull;
    if forced <> [] then
      W.CustomOptions := W.CustomOptions - forced;
  end;
end;

procedure TDocVariant.Clear(var V: TVarData);
begin
  //Assert(V.VType=DocVariantVType);
  TDocVariantData(V).ClearFast;
end;

procedure TDocVariant.Copy(var Dest: TVarData; const Source: TVarData;
  const Indirect: boolean);
begin
  //Assert(Source.VType=DocVariantVType);
  if Indirect then
    SetVariantByRef(variant(Source), variant(Dest))
  else
    CopyByValue(Dest, Source);
end;

procedure TDocVariant.CopyByValue(var Dest: TVarData; const Source: TVarData);
var
  S: TDocVariantData absolute Source;
  D: TDocVariantData absolute Dest;
  i: PtrInt;
begin
  //Assert(Source.VType=DocVariantVType);
  VarClearAndSetType(variant(Dest), PCardinal(@S)^); // VType + VOptions
  pointer(D.VName) := nil; // avoid GPF
  pointer(D.VValue) := nil;
  D.VCount := S.VCount;
  if S.VCount = 0 then
    exit; // no data to copy
  D.VName := S.VName;
  if dvoValueCopiedByReference in S.VOptions then
    D.VValue := S.VValue
  else
  begin
    SetLength(D.VValue, S.VCount);
    for i := 0 to S.VCount - 1 do
      D.VValue[i] := S.VValue[i];
  end;
end;

procedure TDocVariant.Cast(var Dest: TVarData; const Source: TVarData);
begin
  CastTo(Dest, Source, VarType);
end;

procedure TDocVariant.CastTo(var Dest: TVarData; const Source: TVarData;
  const AVarType: TVarType);
var
  json: RawUtf8;
  wasString: boolean;
begin
  if AVarType = VarType then
  begin
    VariantToUtf8(Variant(Source), json, wasString);
    if wasString then
    begin
      VarClear(variant(Dest));
      variant(Dest) := _JsonFast(json); // convert from JSON text
      exit;
    end;
    RaiseCastError;
  end
  else
  begin
    if Source.VType <> VarType then
      RaiseCastError;
    DocVariantType.ToJson(@Source, json);
    RawUtf8ToVariant(json, Dest, AVarType); // convert to JSON text
  end;
end;

procedure TDocVariant.Compare(const Left, Right: TVarData;
  var Relationship: TVarCompareResult);
var
  res: integer;
begin
  res := FastVarDataComp(@Left, @Right, {caseins=}false);
  if res < 0 then
    Relationship := crLessThan
  else if res > 0 then
    Relationship := crGreaterThan
  else
    Relationship := crEqual;
end;

class procedure TDocVariant.New(out aValue: variant;
  aOptions: TDocVariantOptions);
begin
  TDocVariantData(aValue).Init(aOptions);
end;

class procedure TDocVariant.NewFast(out aValue: variant;
  aKind: TDocVariantKind);
begin
  TVarData(aValue) := DV_FAST[aKind];
end;

class procedure TDocVariant.IsOfTypeOrNewFast(var aValue: variant);
begin
  if DocVariantType.IsOfType(aValue) then
    exit;
  VarClear(aValue);
  TVarData(aValue) := DV_FAST[dvUndefined];
end;

class procedure TDocVariant.NewFast(const aValues: array of PDocVariantData;
  aKind: TDocVariantKind);
var
  i: PtrInt;
  def: PDocVariantData;
begin
  def := @DV_FAST[aKind];
  for i := 0 to high(aValues) do
    aValues[i]^ := def^;
end;

class function TDocVariant.New(Options: TDocVariantOptions): Variant;
begin
  VarClear(result{%H-});
  TDocVariantData(result).Init(Options);
end;

class function TDocVariant.NewObject(const NameValuePairs: array of const;
  Options: TDocVariantOptions): variant;
begin
  VarClear(result{%H-});
  TDocVariantData(result).InitObject(NameValuePairs, Options);
end;

class function TDocVariant.NewArray(const Items: array of const;
  Options: TDocVariantOptions): variant;
begin
  VarClear(result{%H-});
  TDocVariantData(result).InitArray(Items, Options);
end;

class function TDocVariant.NewArray(const Items: TVariantDynArray;
  Options: TDocVariantOptions): variant;
begin
  VarClear(result{%H-});
  TDocVariantData(result).InitArrayFromVariants(Items, Options);
end;

class function TDocVariant.NewJson(const Json: RawUtf8;
  Options: TDocVariantOptions): variant;
begin
  _Json(Json, result, Options);
end;

class function TDocVariant.NewUnique(const SourceDocVariant: variant;
  Options: TDocVariantOptions): variant;
begin
  VarClear(result{%H-});
  TDocVariantData(result).InitCopy(SourceDocVariant, Options);
end;

class procedure TDocVariant.GetSingleOrDefault(
  const docVariantArray, default: variant; var result: variant);
var
  vt: cardinal;
begin
  vt := TVarData(docVariantArray).VType;
  if vt = varVariantByRef then
    GetSingleOrDefault(
      PVariant(TVarData(docVariantArray).VPointer)^, default, result)
  else if (vt <> DocVariantVType) or
          (TDocVariantData(docVariantArray).Count <> 1) or
          not TDocVariantData(docVariantArray).IsArray then
    result := default
  else
    result := TDocVariantData(docVariantArray).Values[0];
end;

function DocVariantData(const DocVariant: variant): PDocVariantData;
var
  docv, vt: cardinal;
begin
  result := @DocVariant;
  docv := DocVariantVType;
  vt := result^.VType;
  if vt = docv then
    exit
  else if vt = varVariantByRef then
  begin
    result := PVarData(result)^.VPointer;
    if cardinal(result^.VType) = docv then
      exit;
  end;
  raise EDocVariant.CreateUtf8('DocVariantType.Data(%<>TDocVariant)',
    [ord(result^.VType)]);
end;

{$ifdef FPC_OR_UNICODE} // Delphi has problems inlining this :(
function _Safe(const DocVariant: variant): PDocVariantData;
var
  docv, vt: cardinal;
begin
  result := @DocVariant;
  docv := DocVariantVType;
  vt := result^.VType;
  if vt = docv then
    exit
  else if vt = varVariantByRef then
  begin
    result := PVarData(result)^.VPointer;
    if cardinal(result^.VType) = docv then
      exit;
  end;
  result := @DocVariantDataFake;
end;
{$else} // fallback for Delphi 7/2007
function _Safe(const DocVariant: variant): PDocVariantData;
asm
        mov     ecx, DocVariantVType
        movzx   edx, word ptr [eax].TVarData.VType
        cmp     edx, ecx
        jne     @by
        ret
@ptr:   mov     eax, [eax].TVarData.VPointer
        movzx   edx, word ptr [eax].TVarData.VType
        cmp     edx, ecx
        je      @ok
@by:    cmp     edx, varVariantByRef
        je      @ptr
        lea     eax, [DocVariantDataFake]
@ok:
end;
{$endif FPC_OR_UNICODE}

function _Safe(const DocVariant: variant; out DV: PDocVariantData): boolean;
var
  docv, vt: cardinal;
  v: PDocVariantData;
{$ifdef FPC} // latest Delphi compilers have problems inlining labels
label
  no;
{$endif FPC}
begin
  docv := DocVariantVType;
  v := @DocVariant;
  vt := v^.VType;
  {$ifdef ISDELPHI}
  result := false;
  {$endif ISDELPHI}
  if vt <> docv then
    if vt <> varVariantByRef then
    begin
{$ifdef FPC}
no:  result := false;
{$endif FPC}
     exit;
    end
    else
    begin
      v := PVarData(v)^.VPointer;
      if cardinal(v^.VType) <> docv then
      {$ifdef FPC}
        goto no;
      {$else}
        exit;
      {$endif FPC}
    end;
  DV := v;
  result := true;
end;

function _SafeArray(const Value: variant; out DV: PDocVariantData): boolean;
begin
  result := _Safe(Value, DV) and
            not {%H-}DV^.IsObject;
end;

function _SafeArray(const Value: variant; ExpectedCount: integer;
  out DV: PDocVariantData): boolean; overload;
begin
  result := _Safe(Value, DV) and
            {%H-}DV^.IsArray and
            (DV^.Count = ExpectedCount);
end;

function _SafeObject(const Value: variant; out DV: PDocVariantData): boolean;
begin
  result := _Safe(Value, DV) and
            not {%H-}DV^.IsArray;
end;

function _Safe(const DocVariant: variant;
  ExpectedKind: TDocVariantKind): PDocVariantData;
begin
  if ExpectedKind = dvArray then
  begin
    if _SafeArray(DocVariant, result) then
      exit;
  end
  else if (ExpectedKind = dvObject) and
          _SafeObject(DocVariant, result) then
    exit;
  EDocVariant.RaiseSafe(ExpectedKind);
end;

function _DV(const DocVariant: variant): TDocVariantData;
begin
  result := _Safe(DocVariant)^;
end;

function _DV(const DocVariant: variant;
  ExpectedKind: TDocVariantKind): TDocVariantData;
begin
  result := _Safe(DocVariant, ExpectedKind)^;
end;

function _DV(const DocVariant: variant; var DV: TDocVariantData): boolean;
var
  docv, vt: cardinal;
  v: PDocVariantData;
label
  no;
begin
  docv := DocVariantVType;
  v := @DocVariant;
  vt := v^.VType;
  if vt <> docv then
    if vt <> varVariantByRef then
    begin
no:   result := false;
      exit;
    end
    else
    begin
      v := PVarData(v)^.VPointer;
      if cardinal(v^.VType) <> docv then
        goto no;
    end;
  DV := v^;
  result := true;
end;

function _Csv(const DocVariantOrString: variant): RawUtf8;
begin
  with _Safe(DocVariantOrString)^ do
    if IsArray then
      result := ToCsv
    else if IsObject or
            not VariantToText(DocVariantOrString, result) then
      result := '';
end;

function ObjectToVariant(Value: TObject; EnumSetsAsText: boolean): variant;
const
  OPTIONS: array[boolean] of TTextWriterWriteObjectOptions = (
     [woDontStoreDefault], [woDontStoreDefault, woEnumSetsAsText]);
begin
  ObjectToVariant(Value, result, OPTIONS[EnumSetsAsText]);
end;

function ObjectToVariantDebug(Value: TObject;
  const ContextFormat: RawUtf8; const ContextArgs: array of const;
  const ContextName: RawUtf8): variant;
begin
  ObjectToVariant(Value, result, [woDontStoreDefault, woEnumSetsAsText]);
  if ContextFormat <> '' then
    if ContextFormat[1] = '{' then
      _ObjAddProps([ContextName,
        _JsonFastFmt(ContextFormat, [], ContextArgs)], result)
    else
      _ObjAddProps([ContextName,
        FormatUtf8(ContextFormat, ContextArgs)], result);
end;

procedure ObjectToVariant(Value: TObject; var result: variant;
  Options: TTextWriterWriteObjectOptions);
var
  json: RawUtf8;
begin
  VarClear(result{%H-});
  json := ObjectToJson(Value, Options);
  if PDocVariantData(@result)^.InitJsonInPlace(
      pointer(json), JSON_FAST) = nil then
    VarClear(result);
end;

function SetNameToVariant(Value: cardinal; Info: TRttiCustom;
  FullSetsAsStar: boolean): variant;
var
  bit: PtrInt;
  PS: PShortString;
  arr: TDocVariantData;
begin
  TVarData(arr) := DV_FAST[dvArray];
  if FullSetsAsStar and
     GetAllBits(Value, Info.Cache.EnumMax + 1) then
    arr.AddItem('*')
  else
    with Info.Cache do
    begin
      PS := EnumList;
      for bit := EnumMin to EnumMax do
      begin
        if GetBitPtr(@Value, bit) then
          arr.AddItem(PS^);
        inc(PByte(PS), ord(PS^[0]) + 1); // next item
      end;
    end;
  result := variant(arr);
end;

function SetNameToVariant(Value: cardinal; Info: PRttiInfo;
  FullSetsAsStar: boolean): variant;
begin
  result := SetNameToVariant(Value, Rtti.RegisterType(Info), FullSetsAsStar);
end;

function DocVariantToObject(var doc: TDocVariantData; obj: TObject;
  objRtti: TRttiCustom): boolean;
var
  p: PtrInt;
  prop: PRttiCustomProp;
begin
  if doc.IsObject and
     (doc.Count > 0) and
     (obj <> nil) then
  begin
    if objRtti = nil then
      objRtti := Rtti.RegisterClass(PClass(obj)^);
    for p := 0 to doc.Count - 1 do
    begin
      prop := objRtti.Props.Find(doc.Names[p]);
      if prop <> nil then
        prop^.Prop.SetValue(obj, doc.Values[p]);
    end;
    result := true;
  end
  else
    result := false;
end;

procedure DocVariantToObjArray(var arr: TDocVariantData; var objArray;
  objClass: TClass);
var
  info: TRttiCustom;
  i: PtrInt;
  obj: TObjectDynArray absolute objArray;
begin
  if objClass = nil then
    exit;
  ObjArrayClear(obj);
  if (not arr.IsArray) or
     (arr.Count = 0) then
    exit;
  info := Rtti.RegisterClass(objClass);
  SetLength(obj, arr.Count);
  for i := 0 to arr.Count - 1 do
  begin
    obj[i] := info.ClassNewInstance;
    DocVariantToObject(_Safe(arr.Values[i])^, obj[i], info);
  end;
end;

function ObjectDefaultToVariant(aClass: TClass;
  aOptions: TDocVariantOptions): variant;
var
  tempvoid: TObject;
  json: RawUtf8;
begin
  VarClear(result);
  tempvoid := Rtti.RegisterClass(aClass).ClassNewInstance;
  try
    json := ObjectToJson(tempvoid, [woDontStoreDefault]);
    PDocVariantData(@result)^.InitJsonInPlace(pointer(json), aOptions);
  finally
    tempvoid.Free;
  end;
end;


{$ifdef HASITERATORS}

{ TDocVariantEnumeratorState }

procedure TDocVariantEnumeratorState.Void;
begin
  After := nil;
  Curr := nil;
end;

procedure TDocVariantEnumeratorState.Init(Values: PVariantArray; Count: PtrUInt);
begin
  if Count = 0 then
    Void
  else
  begin
    Curr := pointer(Values);
    After := @Values[Count];
    dec(Curr);
  end;
end;

function TDocVariantEnumeratorState.MoveNext: Boolean;
begin
   inc(Curr);
   result := PtrUInt(Curr) < PtrUInt(After); // Void = nil+1<nil = false
end;

{ TDocVariantFieldsEnumerator }

function TDocVariantFieldsEnumerator.GetCurrent: TDocVariantFields;
begin
  result.Name := Name;
  result.Value := State.Curr;
end;

function TDocVariantFieldsEnumerator.MoveNext: Boolean;
begin
  result := State.MoveNext;
  if result and
     Assigned(Name) then
    inc(Name);
end;

function TDocVariantFieldsEnumerator.GetEnumerator: TDocVariantFieldsEnumerator;
begin
  result := self;
end;

{ TDocVariantFieldNamesEnumerator }

function TDocVariantFieldNamesEnumerator.MoveNext: Boolean;
begin
  inc(Curr);
  result := PtrUInt(Curr) < PtrUInt(After);
end;

function TDocVariantFieldNamesEnumerator.GetEnumerator: TDocVariantFieldNamesEnumerator;
begin
  result := self;
end;

{ TDocVariantItemsEnumerator }

function TDocVariantItemsEnumerator.MoveNext: Boolean;
begin
   result := State.MoveNext;
end;

function TDocVariantItemsEnumerator.GetEnumerator: TDocVariantItemsEnumerator;
begin
  result := self;
end;

{ TDocVariantObjectsEnumerator }

function TDocVariantObjectsEnumerator.MoveNext: Boolean;
var
  vt: cardinal;
  vd: PVarData; // inlined while not DocVariant.IsOfType() + Value := _Safe()
begin
  repeat
    inc(State.Curr);
    vd := pointer(State.Curr);
    if PtrUInt(vd) >= PtrUInt(State.After) then
      break;
    repeat
      vt := vd^.VType;
      if vt = DocVariantVType then
      begin
        Value := pointer(vd);
        result := true;
        exit;
      end;
      if vt <> varVariantByRef then
        break;
      vd := vd^.VPointer;
    until false;
  until false;
  result := false;
end;

function TDocVariantObjectsEnumerator.GetEnumerator: TDocVariantObjectsEnumerator;
begin
  result := self;
end;

{$endif HASITERATORS}


{ TDocVariantData }

function TDocVariantData.GetValueIndex(const aName: RawUtf8): integer;
begin
  result := GetValueIndex(Pointer(aName), Length(aName), IsCaseSensitive);
end;

function TDocVariantData.GetCapacity: integer;
begin
  result := length(VValue);
end;

function TDocVariant.InternNames: TRawUtf8Interning;
begin
  result := fInternNames;
  if result = nil then
    result := CreateInternNames;
end;

function TDocVariant.CreateInternNames: TRawUtf8Interning;
begin
  fInternSafe.Lock;
  try
    if fInternNames = nil then
      fInternNames := TRawUtf8Interning.Create;
  finally
    fInternSafe.UnLock;
  end;
  result := fInternNames;
end;

function TDocVariant.InternValues: TRawUtf8Interning;
begin
  result := fInternValues;
  if fInternValues = nil then
    result := CreateInternValues;
end;

function TDocVariant.CreateInternValues: TRawUtf8Interning;
begin
  fInternSafe.Lock;
  try
    if fInternValues = nil then
      fInternValues := TRawUtf8Interning.Create;
  finally
    fInternSafe.UnLock;
  end;
  result := fInternValues;
end;

procedure TDocVariantData.InternalSetValue(aIndex: PtrInt; const aValue: variant);
begin
  SetVariantByValue(aValue, VValue[aIndex]); // caller ensured that aIndex is OK
  if dvoInternValues in VOptions then
    InternalUniqueValue(aIndex);
end;

procedure TDocVariantData.InternalUniqueValue(aIndex: PtrInt);
begin
  DocVariantType.InternValues.UniqueVariant(VValue[aIndex]);
end;

procedure TDocVariantData.SetOptions(const opt: TDocVariantOptions);
begin
  VOptions := (opt - [dvoIsArray, dvoIsObject]) +
              (VOptions * [dvoIsArray, dvoIsObject]);
end;

procedure TDocVariantData.InitClone(const CloneFrom: TDocVariantData);
begin
  TRttiVarData(self).VType := TRttiVarData(CloneFrom).VType // VType+VOptions
    and not ((1 shl (ord(dvoIsObject) + 16)) + (1 shl (ord(dvoIsArray) + 16)));
  pointer(VName) := nil; // to avoid GPF
  pointer(VValue) := nil;
  VCount := 0;
end;

function TDocVariantData.InitFrom(const CloneFrom: TDocVariantData;
  CloneValues, MakeUnique: boolean): PVariant;
begin
  TRttiVarData(self).VType := TRttiVarData(CloneFrom).VType; // VType+VOptions
  VCount := CloneFrom.VCount;
  if MakeUnique then
    VName := copy(CloneFrom.VName) // new array, but byref names
  else
    VName := CloneFrom.VName;      // byref copy of the whole array
  if CloneValues then
    if MakeUnique then
      VValue := copy(CloneFrom.VValue) // new array, but byref values
    else
      VValue := CloneFrom.VValue       // byref copy of the whole array
  else
    SetLength(VValue, VCount);         // setup void values
  result := pointer(VValue);
end;

procedure TDocVariantData.Init(aOptions: TDocVariantOptions);
begin
  VType := DocVariantVType;
  aOptions := aOptions - [dvoIsArray, dvoIsObject];
  VOptions := aOptions;
  pointer(VName) := nil; // to avoid GPF when mapped within a TVarData/variant
  pointer(VValue) := nil;
  VCount := 0;
end;

procedure TDocVariantData.Init(aOptions: TDocVariantOptions;
  aKind: TDocVariantKind);
var
  opt: cardinal; // Intel has latency on word-level memory access
begin
  aOptions := aOptions - [dvoIsArray, dvoIsObject];
  if aKind <> dvUndefined then
    if aKind = dvArray then
      include(aOptions, dvoIsArray)
    else
      include(aOptions, dvoIsObject);
  opt := word(aOptions);
  TRttiVarData(self).VType := DocVariantVType + opt shl 16; // VType+VOptions
  pointer(VName) := nil; // to avoid GPF
  pointer(VValue) := nil;
  VCount := 0;
end;

procedure TDocVariantData.Init(aModel: TDocVariantModel; aKind: TDocVariantKind);
begin
  Init(JSON_[aModel], aKind);
end;

procedure TDocVariantData.InitFast(aKind: TDocVariantKind);
begin
  TVarData(self) := DV_FAST[aKind];
end;

procedure TDocVariantData.InitFast(InitialCapacity: integer;
  aKind: TDocVariantKind);
begin
  TVarData(self) := DV_FAST[aKind];
  if aKind = dvObject then
    SetLength(VName, InitialCapacity);
  SetLength(VValue, InitialCapacity);
end;

procedure TDocVariantData.InitObject(const NameValuePairs: array of const;
  aOptions: TDocVariantOptions);
begin
  Init(aOptions, dvObject);
  AddNameValuesToObject(NameValuePairs);
end;

procedure TDocVariantData.InitObject(const NameValuePairs: array of const;
  Model: TDocVariantModel);
begin
  Init(Model, dvObject);
  AddNameValuesToObject(NameValuePairs);
end;

procedure TDocVariantData.AddNameValuesToObject(
  const NameValuePairs: array of const);
var
  n, arg: PtrInt;
  tmp: variant;
begin
  n := length(NameValuePairs);
  if (n = 0) or
     (n and 1 = 1) or
     IsArray then
    exit; // nothing to add
  include(VOptions, dvoIsObject);
  n := n shr 1;
  if length(VValue) < VCount + n then
  begin
    SetLength(VValue, VCount + n);
    SetLength(VName, VCount + n);
  end;
  for arg := 0 to n - 1 do
  begin
    VarRecToUtf8(NameValuePairs[arg * 2], VName[arg + VCount]);
    if dvoInternNames in VOptions then
      DocVariantType.InternNames.UniqueText(VName[arg + VCount]);
    if dvoValueCopiedByReference in VOptions then
      VarRecToVariant(NameValuePairs[arg * 2 + 1], VValue[arg + VCount])
    else
    begin
      VarRecToVariant(NameValuePairs[arg * 2 + 1], tmp);
      SetVariantByValue(tmp, VValue[arg + VCount]);
    end;
    if dvoInternValues in VOptions then
      InternalUniqueValue(arg + VCount);
  end;
  inc(VCount, n);
end;

{$ifndef PUREMORMOT2}
procedure TDocVariantData.AddOrUpdateNameValuesToObject(
  const NameValuePairs: array of const);
begin
  Update(NameValuePairs);
end;
{$endif PUREMORMOT2}

procedure TDocVariantData.Update(const NameValuePairs: array of const);
var
  n, arg: PtrInt;
  nam: RawUtf8;
  val: Variant;
begin
  n := length(NameValuePairs);
  if (n = 0) or
     (n and 1 = 1) or
     IsArray then
    exit; // nothing to add
  for arg := 0 to (n shr 1) - 1 do
  begin
    VarRecToUtf8(NameValuePairs[arg * 2], nam);
    VarRecToVariant(NameValuePairs[arg * 2 + 1], val);
    AddOrUpdateValue(nam, val)
  end;
end;

procedure TDocVariantData.AddOrUpdateObject(const NewValues: variant;
  OnlyAddMissing: boolean; RecursiveUpdate: boolean);
var
  n, idx: PtrInt;
  new: PDocVariantData;
  wasAdded: boolean;
begin
  new := _Safe(NewValues);
  if not IsArray and
     not new^.IsArray then
    for n := 0 to new^.Count - 1 do
    begin
      idx := AddOrUpdateValue(
        new^.names[n], new^.Values[n], @wasAdded, OnlyAddMissing);
      if RecursiveUpdate and
         not wasAdded then
        TDocVariantData(Values[idx]).AddOrUpdateObject(
          new^.Values[n], OnlyAddMissing, true);
    end;
end;

procedure TDocVariantData.InitArray(const aItems: array of const;
  aOptions: TDocVariantOptions);
var
  arg: PtrInt;
  tmp: variant;
begin
  Init(aOptions, dvArray);
  if high(aItems) >= 0 then
  begin
    VCount := length(aItems);
    SetLength(VValue, VCount);
    if dvoValueCopiedByReference in VOptions then
      for arg := 0 to high(aItems) do
        VarRecToVariant(aItems[arg], VValue[arg])
    else
      for arg := 0 to high(aItems) do
      begin
        VarRecToVariant(aItems[arg], tmp);
        InternalSetValue(arg, tmp);
      end;
  end;
end;

procedure TDocVariantData.InitArray(const aItems: array of const;
  aModel: TDocVariantModel);
begin
  InitArray(aItems, JSON_[aModel]);
end;

procedure TDocVariantData.InitArrayFromVariants(const aItems: TVariantDynArray;
  aOptions: TDocVariantOptions; aItemsCopiedByReference: boolean; aCount: integer);
begin
  if aItems = nil then
    TRttiVarData(self).VType := varNull
  else
  begin
    Init(aOptions, dvArray);
    if aCount < 0 then
      VCount := length(aItems)
    else
      VCount := aCount;
    VValue := aItems; // fast by-reference copy of VValue[]
    if not aItemsCopiedByReference then
      InitCopy(variant(self), aOptions);
  end;
end;

procedure TDocVariantData.InitArrayFromObjectValues(const aObject: variant;
  aOptions: TDocVariantOptions; aItemsCopiedByReference: boolean);
var
  dv: PDocVariantData;
begin
  if _SafeObject(aObject, dv) then
    InitArrayFromVariants(dv^.Values, aOptions, aItemsCopiedByReference, dv^.Count)
  else
    TRttiVarData(self).VType := varNull;
end;

procedure TDocVariantData.InitArrayFromObjectNames(const aObject: variant;
  aOptions: TDocVariantOptions; aItemsCopiedByReference: boolean);
var
  dv: PDocVariantData;
begin
  if _SafeObject(aObject, dv) then
    InitArrayFrom(dv^.Names, aOptions, dv^.Count)
  else
    TRttiVarData(self).VType := varNull;
end;

function _InitArray(out aDest: TDocVariantData; aOptions: TDocVariantOptions;
  aCount: integer; const aItems): PRttiVarData;
begin
  if aCount < 0 then
    aCount := length(TByteDynArray(aItems));
  if aCount = 0 then
  begin
    TRttiVarData(aDest).VType := varNull;
    result := nil;
    exit;
  end;
  aDest.Init(aOptions, dvArray);
  aDest.VCount := aCount;
  SetLength(aDest.VValue, aCount);
  result := pointer(aDest.VValue);
end;

procedure TDocVariantData.InitArrayFromObjArray(const ObjArray;
  aOptions: TDocVariantOptions; aWriterOptions: TTextWriterWriteObjectOptions;
  aCount: integer);
var
  ndx: PtrInt;
  aItems: TObjectDynArray absolute ObjArray;
begin
  _InitArray(self, aOptions, aCount, aItems);
  for ndx := 0 to VCount - 1 do
    ObjectToVariant(aItems[ndx], VValue[ndx], aWriterOptions);
end;

procedure TDocVariantData.InitArrayFrom(const aItems: TRawUtf8DynArray;
  aOptions: TDocVariantOptions; aCount: integer);
var
  ndx: PtrInt;
  v: PRttiVarData;
begin
  v := _InitArray(self, aOptions, aCount, aItems);
  for ndx := 0 to VCount - 1 do
  begin
    v^.VType := varString;
    RawUtf8(v^.Data.VAny) := aItems[ndx];
    inc(v);
  end;
end;

procedure TDocVariantData.InitArrayFrom(const aItems: TIntegerDynArray;
  aOptions: TDocVariantOptions; aCount: integer);
var
  ndx: PtrInt;
  v: PRttiVarData;
begin
  v := _InitArray(self, aOptions, aCount, aItems);
  for ndx := 0 to VCount - 1 do
  begin
    v^.VType := varInteger;
    v^.Data.VInteger := aItems[ndx];
    inc(v);
  end;
end;

procedure TDocVariantData.InitArrayFrom(const aItems: TInt64DynArray;
  aOptions: TDocVariantOptions; aCount: integer);
var
  ndx: PtrInt;
  v: PRttiVarData;
begin
  v := _InitArray(self, aOptions, aCount, aItems);
  for ndx := 0 to VCount - 1 do
  begin
    v^.VType := varInt64;
    v^.Data.VInt64 := aItems[ndx];
    inc(v);
  end;
end;

procedure TDocVariantData.InitArrayFrom(const aItems: TDoubleDynArray;
  aOptions: TDocVariantOptions; aCount: integer);
var
  ndx: PtrInt;
  v: PRttiVarData;
begin
  v := _InitArray(self, aOptions, aCount, aItems);
  for ndx := 0 to VCount - 1 do
  begin
    v^.VType := varDouble;
    v^.Data.VDouble := aItems[ndx];
    inc(v);
  end;
end;

procedure TDocVariantData.InitArrayFrom(var aItems; ArrayInfo: PRttiInfo;
  aOptions: TDocVariantOptions; ItemsCount: PInteger);
var
  da: TDynArray;
begin
  da.Init(ArrayInfo, aItems, ItemsCount);
  InitArrayFrom(da, aOptions);
end;

procedure TDocVariantData.InitArrayFrom(const aItems: TDynArray;
  aOptions: TDocVariantOptions);
var
  n: integer;
  pb: PByte;
  v: PVarData;
  item: TRttiCustom;
  json: RawUtf8;
begin
  Init(aOptions, dvArray);
  n := aItems.Count;
  item := aItems.Info.ArrayRtti;
  if (n = 0) or
     (item = nil) then
    exit;
  if item.Kind in (rkRecordOrDynArrayTypes + [rkClass]) then
  begin
    // use temporary non-expanded JSON conversion for complex nested content
    aItems.SaveToJson(json, [twoNonExpandedArrays]);
    if (json <> '') and
       (json[1] = '{') then
      // should be a non-expanded array, not JSON_BASE64_MAGIC_QUOTE_C
      InitArrayFromResults(pointer(json), length(json), aOptions);
  end
  else
  begin
    // handle array of simple types
    VCount := n;
    SetLength(VValue, n);
    pb := aItems.Value^;
    v := pointer(VValue);
    repeat
      inc(pb, item.ValueToVariant(pb, v^));
      inc(v);
      dec(n);
    until n = 0;
  end;
end;

{ Some numbers on Linux x86_64:
    TDocVariant exp in 135.36ms i.e. 1.1M/s, 144.8 MB/s
    TDocVariant exp no guess in 139.10ms i.e. 1.1M/s, 140.9 MB/s
    TDocVariant exp dvoIntern in 139.19ms i.e. 1.1M/s, 140.8 MB/s
    TDocVariant FromResults exp in 60.86ms i.e. 2.5M/s, 322 MB/s
    TDocVariant FromResults not exp in 47ms i.e. 3.3M/s, 183.4 MB/s
}

function TDocVariantData.InitArrayFromResults(Json: PUtf8Char; JsonLen: PtrInt;
  aOptions: TDocVariantOptions): boolean;
var
  J: PUtf8Char;
  fieldcount, rowcount, capa, r, f: PtrInt;
  info: TGetJsonField;
  dv: PDocVariantData;
  val: PVariant;
  proto: TDocVariantData;
begin
  result := false;
  Init(aOptions, dvArray);
  info.Json := GotoNextNotSpace(Json);
  if IsNotExpandedBuffer(info.Json, Json + JsonLen, fieldcount, rowcount) then
  begin
    // A. Not Expanded (more optimized) format as array of values
    // {"fieldCount":2,"values":["f1","f2","1v1",1v2,"2v1",2v2...],"rowCount":20}
    // 1. check rowcount and fieldcount
    if (rowcount < 0) or // IsNotExpandedBuffer() detected invalid input
       (fieldcount = 0) then
      exit;
    // 2. initialize the object prototype with the trailing field names
    proto.Init(aOptions, dvObject);
    proto.Capacity := fieldcount;
    for f := 1 to fieldcount do
    begin
      info.GetJsonField;
      if not info.WasString then
        exit; // should start with field names
      proto.AddValue(info.Value, info.ValueLen, null); // set proper field name
    end;
    // 3. fill all nested objects from incoming values
    SetLength(VValue, rowcount);
    dv := pointer(VValue);
    for r := 1 to rowcount do
    begin
      val := dv^.InitFrom(proto, {values=}false); // names byref + void values
      for f := 1 to fieldcount do
      begin
        JsonToAnyVariant(val^, info, @aOptions);
        inc(val);
      end;
      if info.Json = nil then
        exit;
      inc(dv); // next object
    end;
  end
  else
  begin
    // B. Expanded format as array of objects (each with field names)
    // [{"f1":"1v1","f2":1v2},{"f2":"2v1","f2":2v2}...]
    // 1. get first object (will reuse its field names)
    info.Json := GotoFieldCountExpanded(info.Json);
    if (info.Json = nil) or
       (info.Json^ = ']') then
      exit; // [] -> valid, but void data
    info.Json := proto.InitJsonInPlace(info.Json, aOptions, @info.EndOfObject);
    if info.Json = nil then
      exit;
    if info.EndOfObject = ']' then
    begin
      AddItem(variant(proto)); // single item array
      result := true;
      exit;
    end;
    rowcount := 0;
    capa := 16;
    SetLength(VValue, capa);
    dv := pointer(VValue);
    dv^ := proto;
    // 2. get values (assume fieldcount are always the same as in the first object)
    repeat
      J := info.Json;
      while (J^ <> '{') and
            (J^ <> ']') do // go to next object beginning
        if J^ = #0 then
          exit
        else
          inc(J);
      inc(rowcount);
      if J^ = ']' then
        break;
      info.Json := J + 1; // jmp '}'
      if rowcount = capa then
      begin
        capa := NextGrow(capa);
        SetLength(VValue, capa);
        dv := @VValue[rowcount];
      end
      else
        inc(dv);
      val := dv^.InitFrom(proto, {values=}false);
      for f := 1 to proto.Count do
      begin
        info.Json := GotoEndJsonItemString(info.Json); // ignore field names
        if info.Json = nil then
          exit;
        inc(info.Json); // ignore jcEndOfJsonFieldOr0
        JsonToAnyVariant(val^, info, @aOptions);
        if info.Json = nil then
          exit;
        inc(val);
      end;
      if info.EndOfObject<> '}' then
       exit;
    until false;
  end;
  VCount := rowcount;
  result := true;
end;

function TDocVariantData.InitArrayFromResults(const Json: RawUtf8;
  aOptions: TDocVariantOptions): boolean;
var
  tmp: TSynTempBuffer;
begin
  tmp.Init(Json);
  try
    result := InitArrayFromResults(tmp.buf, tmp.len, aOptions);
  finally
    tmp.Done;
  end;
end;

function TDocVariantData.InitArrayFromResults(const Json: RawUtf8;
  aModel: TDocVariantModel): boolean;
begin
  result := InitArrayFromResults(Json, JSON_[aModel]);
end;

procedure TDocVariantData.InitObjectFromVariants(const aNames: TRawUtf8DynArray;
  const aValues: TVariantDynArray; aOptions: TDocVariantOptions);
begin
  VCount := length(aNames);
  if (aNames = nil) or
     (length(aValues) <> VCount) then
    VType := varNull
  else
  begin
    VType := DocVariantVType;
    VOptions := aOptions + [dvoIsObject];
    pointer(VName) := nil;
    VName := aNames; // fast by-reference copy of VName[] and VValue[]
    pointer(VValue) := nil;
    VValue := aValues;
  end;
end;

procedure TDocVariantData.InitObjectFromPath(const aPath: RawUtf8;
  const aValue: variant; aOptions: TDocVariantOptions; aPathDelim: AnsiChar);
var
  right: RawUtf8;
begin
  if aPath = '' then
    VType := varNull
  else
  begin
    Init(aOptions, dvObject);
    VCount := 1;
    SetLength(VName, 1);
    SetLength(VValue, 1);
    Split(aPath, aPathDelim, VName[0], right);
    if right = '' then
      VValue[0] := aValue
    else
      PDocVariantData(@VValue[0])^.InitObjectFromPath(
        right, aValue, aOptions, aPathDelim);
  end;
end;

function TDocVariantData.InitJsonInPlace(Json: PUtf8Char;
  aOptions: TDocVariantOptions; aEndOfObject: PUtf8Char): PUtf8Char;
var
  info: TGetJsonField;
  Name: PUtf8Char;
  NameLen: integer;
  n, cap: PtrInt;
  Val: PVariant;
  intnames, intvalues: TRawUtf8Interning;
begin
  Init(aOptions);
  result := nil;
  if Json = nil then
    exit;
  if dvoInternValues in VOptions then
    intvalues := DocVariantType.InternValues
  else
    intvalues := nil;
  while (Json^ <= ' ') and
        (Json^ <> #0) do
    inc(Json);
  case Json^ of
    '[':
      begin
        repeat
          inc(Json);
          if Json^ = #0 then
            exit;
        until Json^ > ' ';
        include(VOptions, dvoIsArray);
        if Json^ = ']' then
          // void but valid input array
          Json := GotoNextNotSpace(Json + 1)
        else
        begin
          if dvoJsonParseDoNotGuessCount in VOptions then
            cap := 8 // with a lot of nested objects -> best to ignore
          else
          begin
            // guess of the Json array items count - prefetch up to 64KB of input
            cap := abs(JsonArrayCount(Json, Json + JSON_PREFETCH));
            if cap = 0 then
              exit; // invalid content
          end;
          SetLength(VValue, cap);
          Val := pointer(VValue);
          n := 0;
          info.Json := Json;
          repeat
            if n = cap then
            begin
              // grow if our initial guess was aborted due to huge input
              cap := NextGrow(cap);
              SetLength(VValue, cap);
              Val := @VValue[n];
            end;
            // unserialize the next item
            JsonToAnyVariant(val^, info, @VOptions);
            if info.Json = nil then
              break; // invalid input
            if intvalues <> nil then
              intvalues.UniqueVariant(val^);
            inc(Val);
            inc(n);
          until info.EndOfObject = ']';
          Json := info.Json;
          if Json = nil then
          begin
            // invalid input
            VValue := nil;
            exit;
          end;
          // ok - but no SetLength(..,VCount) if NextGrow() on huge input
          VCount := n;
        end;
      end;
    '{':
      begin
        repeat
          inc(Json);
          if Json^ = #0 then
            exit;
        until Json^ > ' ';
        include(VOptions, dvoIsObject);
        if Json^ = '}' then
          // void but valid input object
          Json := GotoNextNotSpace(Json + 1)
        else
        begin
          if dvoJsonParseDoNotGuessCount in VOptions then
            cap := 4 // with a lot of nested documents -> best to ignore
          else
          begin
            // guess of the Json object properties count - prefetch up to 64KB
            cap := JsonObjectPropCount(Json, Json + JSON_PREFETCH);
            if cap = 0 then
              exit // invalid content (was <0 if early abort)
            else if cap < 0 then
            begin // nested or huge objects are evil -> no more guess
              cap := -cap;
              include(VOptions, dvoJsonParseDoNotGuessCount);
            end;
          end;
          if dvoInternNames in VOptions then
            intnames := DocVariantType.InternNames
          else
            intnames := nil;
          SetLength(VValue, cap);
          Val := pointer(VValue);
          SetLength(VName, cap);
          n := 0;
          info.Json := Json;
          repeat
            // see http://docs.mongodb.org/manual/reference/mongodb-extended-Json
            Name := GetJsonPropName(info.Json, @NameLen);
            if Name = nil then
              break; // invalid input
            if n = cap then
            begin
              // grow if our initial guess was aborted due to huge input
              cap := NextGrow(cap);
              SetLength(VName, cap);
              SetLength(VValue, cap);
              Val := @VValue[n];
            end;
            JsonToAnyVariant(Val^, info, @VOptions);
            if info.Json = nil then
              if info.EndOfObject = '}' then // valid object end
                info.Json := @NULCHAR
              else
                break; // invalid input
            if NameLen <> 0 then // we just ignore void "":xxx field names
            begin
              if intnames <> nil then
                intnames.Unique(VName[n], Name, NameLen)
              else
                FastSetString(VName[n], Name, NameLen);
              if intvalues <> nil then
                intvalues.UniqueVariant(Val^);
              inc(n);
              inc(Val);
            end;
          until info.EndOfObject = '}';
          Json := info.Json;
          if (Name = nil) or
             (Json = nil) then
          begin
            // invalid input
            VName := nil;
            VValue := nil;
            exit;
          end;
          // ok - but no SetLength(..,VCount) if NextGrow() on huge input
          VCount := n;
        end;
      end;
    'n',
    'N':
      begin
        if IdemPChar(Json + 1, 'ULL') then
        begin
          include(VOptions, dvoIsObject);
          result := GotoNextNotSpace(Json + 4);
        end;
        exit;
      end;
  else
    exit;
  end;
  while (Json^ <= ' ') and
        (Json^ <> #0) do
    inc(Json);
  if aEndOfObject <> nil then
    aEndOfObject^ := Json^;
  if Json^ <> #0 then
    repeat
      inc(Json)
    until (Json^ = #0) or
          (Json^ > ' ');
  result := Json; // indicates successfully parsed
end;

function TDocVariantData.InitJson(const Json: RawUtf8;
  aOptions: TDocVariantOptions): boolean;
var
  tmp: TSynTempBuffer;
begin
  if Json = '' then
    result := false
  else
  begin
    tmp.Init(Json);
    try
      result := InitJsonInPlace(tmp.buf, aOptions) <> nil;
    finally
      tmp.Done;
    end;
  end;
end;

function TDocVariantData.InitJson(const Json: RawUtf8; aModel: TDocVariantModel): boolean;
begin
  result := InitJson(Json, JSON_[aModel]);
end;

function TDocVariantData.InitJsonFromFile(const FileName: TFileName;
  aOptions: TDocVariantOptions): boolean;
begin
  result := InitJsonInPlace(pointer(RawUtf8FromFile(FileName)), aOptions) <> nil;
end;

procedure TDocVariantData.InitCsv(aCsv: PUtf8Char; aOptions: TDocVariantOptions;
  NameValueSep, ItemSep: AnsiChar; DoTrim: boolean);
var
  n, v: RawUtf8;
  val: variant;
begin
  Init(aOptions, dvObject);
  while aCsv <> nil do
  begin
    GetNextItem(aCsv, NameValueSep, n);
    if ItemSep = #10 then
      GetNextItemTrimedCRLF(aCsv, v)
    else
      GetNextItem(aCsv, ItemSep, v);
    if DoTrim then
      TrimSelf(v);
    if n = '' then
      break;
    RawUtf8ToVariant(v, val);
    AddValue(n, val);
  end;
end;

procedure TDocVariantData.InitCsv(const aCsv: RawUtf8; aOptions: TDocVariantOptions;
  NameValueSep, ItemSep: AnsiChar; DoTrim: boolean);
begin
  InitCsv(pointer(aCsv), aOptions, NameValueSep, ItemSep, DoTrim);
end;

procedure TDocVariantData.InitCopy(const SourceDocVariant: variant;
  aOptions: TDocVariantOptions);
var
  ndx: PtrInt;
  vt: cardinal;
  Source: PDocVariantData;
  SourceVValue: TVariantDynArray;
  Handler: TCustomVariantType;
  v: PVarData;
begin
  with TVarData(SourceDocVariant) do
    if cardinal(VType) = varVariantByRef then
      Source := VPointer
    else
      Source := @SourceDocVariant;
  if cardinal(Source^.VType) <> DocVariantVType then
    raise EDocVariant.CreateUtf8(
      'No TDocVariant for InitCopy(%)', [ord(Source.VType)]);
  SourceVValue := Source^.VValue; // local fast per-reference copy
  if Source <> @self then
  begin
    VType := Source^.VType;
    VCount := Source^.VCount;
    pointer(VName) := nil;  // avoid GPF
    pointer(VValue) := nil;
    aOptions := aOptions - [dvoIsArray, dvoIsObject]; // may not be same as Source
    if Source^.IsArray then
      include(aOptions, dvoIsArray)
    else if Source^.IsObject then
    begin
      include(aOptions, dvoIsObject);
      SetLength(VName, VCount);
      for ndx := 0 to VCount - 1 do
        VName[ndx] := Source^.VName[ndx]; // manual copy is needed
      if (dvoInternNames in aOptions) and
         not (dvoInternNames in Source^.Options) then
        with DocVariantType.InternNames do
          for ndx := 0 to VCount - 1 do
            UniqueText(VName[ndx]);
    end;
    VOptions := aOptions;
  end
  else
  begin
    SetOptions(aOptions);
    VariantDynArrayClear(VValue); // full copy of all values
  end;
  if VCount > 0 then
  begin
    SetLength(VValue, VCount);
    for ndx := 0 to VCount - 1 do
    begin
      v := @SourceVValue[ndx];
      repeat
        vt := v^.VType;
        if vt <> varVariantByRef then
          break;
        v := v^.VPointer;
      until false;
      if vt < varFirstCustom then
        // simple string/number types copy
        VValue[ndx] := variant(v^)
      else if vt = DocVariantVType then
        // direct recursive copy for TDocVariant
        TDocVariantData(VValue[ndx]).InitCopy(variant(v^), VOptions)
      else if FindCustomVariantType(vt, Handler) then
        if Handler.InheritsFrom(TSynInvokeableVariantType) then
          TSynInvokeableVariantType(Handler).CopyByValue(
            TVarData(VValue[ndx]), v^)
        else
          Handler.Copy(
            TVarData(VValue[ndx]), v^, false)
      else
        VValue[ndx] := variant(v^); // default copy
    end;
    if dvoInternValues in VOptions then
      with DocVariantType.InternValues do
        for ndx := 0 to VCount - 1 do
          UniqueVariant(VValue[ndx]);
  end;
  VariantDynArrayClear(SourceVValue);
end;

procedure TDocVariantData.ClearFast;
begin
  TRttiVarData(self).VType := 0; // clear VType and VOptions
  FastDynArrayClear(@VName, TypeInfo(RawUtf8));
  FastDynArrayClear(@VValue, TypeInfo(variant));
  VCount := 0;
end;

procedure TDocVariantData.Clear;
begin
  if cardinal(VType) = DocVariantVType then
    ClearFast
  else
    VarClear(variant(self));
end;

procedure TDocVariantData.Reset;
var
  backup: TDocVariantOptions;
begin
  if VCount = 0 then
    exit;
  backup := VOptions - [dvoIsArray, dvoIsObject];
  ClearFast;
  VOptions := backup;
  VType := DocVariantVType;
end;

procedure TDocVariantData.FillZero;
var
  ndx: PtrInt;
begin
  for ndx := 0 to VCount - 1 do
    mormot.core.variants.FillZero(VValue[ndx]);
  Reset;
end;

function TDocVariantData.GetModel(out model: TDocVariantModel): boolean;
var
  opt: TDocVariantOptions;
  ndx: PtrInt;
begin
  opt := VOptions - [dvoIsArray, dvoIsObject, dvoJsonParseDoNotGuessCount];
  ndx := WordScanIndex(@JSON_, ord(high(TDocVariantModel)) + 1, word(opt));
  if ndx < 0 then
    result := false
  else
  begin
    model := TDocVariantModel(ndx);
    result := true;
  end;
end;

procedure TDocVariantData.SetCount(aCount: integer);
begin
  VCount := aCount;
end;

function TDocVariantData.Compare(const Another: TDocVariantData;
  CaseInsensitive: boolean): integer;
var
  j, n: PtrInt;
  nameCmp: TDynArraySortCompare;
begin
  // first validate the type: as { or [ in JSON
  nameCmp := nil;
  if IsArray then
  begin
    if not Another.IsArray then
    begin
      result := -1;
      exit;
    end;
  end
  else if IsObject then
    if not Another.IsObject then
    begin
      result := 1;
      exit;
    end
    else
      nameCmp := SortDynArrayAnsiStringByCase[not IsCaseSensitive];
  // compare as many in-order content as possible
  n := Another.VCount;
  if VCount < n then
    n := VCount;
  for j := 0 to n - 1 do
  begin
    if Assigned(nameCmp) then
    begin // each name should match
      result := nameCmp(VName[j], Another.VName[j]);
      if result <> 0 then
        exit;
    end;
    result := FastVarDataComp(@VValue[j], @Another.VValue[j], CaseInsensitive);
    if result <> 0 then // each value should match
      exit;
  end;
  // all content did match -> difference is now about the document count
  result := VCount - Another.VCount;
end;

function TDocVariantData.CompareObject(const ObjFields: array of RawUtf8;
  const Another: TDocVariantData; CaseInsensitive: boolean): integer;
var
  f: PtrInt;
  ndx: integer;
  v1, v2: PVarData;
begin
  if IsObject then
    if Another.IsObject then
    begin
      // compare Object, Object by specified fields
      if high(ObjFields) < 0 then
      begin
        result := Compare(Another, CaseInsensitive);
        exit;
      end;
      for f := 0 to high(ObjFields) do
      begin
        v1 := GetVarData(ObjFields[f], nil, @ndx);
        if (cardinal(ndx) < cardinal(Another.VCount)) and
           (SortDynArrayAnsiStringByCase[not IsCaseSensitive](
              ObjFields[f], Another.VName[ndx]) = 0) then
          v2 := @Another.VValue[ndx] // ObjFields are likely at the same position
        else
          v2 := Another.GetVarData(ObjFields[f]); // full safe field name lookup
        result := FastVarDataComp(v1, v2, CaseInsensitive);
        if result <> 0 then // each value should match
          exit;
      end;
      // all fields did match -> difference is now about the document size
      result := VCount - Another.VCount;
    end
    else
      result := 1   // Object, not Object
  else if Another.IsObject then
    result := -1  // not Object, Object
  else
    result := 0;  // not Object, not Object
end;

function TDocVariantData.Equals(const Another: TDocVariantData;
  CaseInsensitive: boolean): boolean;
begin
  result := Compare(Another, CaseInsensitive) = 0;
end;

function TDocVariantData.Compare(const aName: RawUtf8; const aValue: variant;
  aCaseInsensitive: boolean): integer;
var
  v: PVariant;
begin
  if (cardinal(VType) = DocVariantVType) and
     GetObjectProp(aName, v{%H-}) then
    result := FastVarDataComp(pointer(v), @aValue, aCaseInsensitive)
  else
    result := -1;
end;

function TDocVariantData.Equals(const aName: RawUtf8; const aValue: variant;
  aCaseInsensitive: boolean): boolean;
var
  v: PVariant;
begin
  result := (cardinal(VType) = DocVariantVType) and
            GetObjectProp(aName, v{%H-}) and
            (FastVarDataComp(@aValue, pointer(v), aCaseInsensitive) = 0);
end;

function TDocVariantData.InternalAdd(aName: PUtf8Char; aNameLen: integer): integer;
var
  tmp: RawUtf8; // so that the caller won't need to reserve such a temp var
begin
  FastSetString(tmp, aName, aNameLen);
  result := InternalAdd(tmp, -1);
end;

function TDocVariantData.InternalAdd(
  const aName: RawUtf8; aIndex: integer): integer;
var
  len: integer;
begin
  // validate consistent add/insert
  if aName <> '' then
  begin
    if IsArray then
      raise EDocVariant.CreateUtf8(
        'Add: Unexpected [%] object property in an array', [aName]);
    if not IsObject then
    begin
      VType := DocVariantVType; // may not be set yet
      include(VOptions, dvoIsObject);
    end;
  end
  else
  begin
    if IsObject then
      raise EDocVariant.Create('Add: Unexpected array item in an object');
    if not IsArray then
    begin
      VType := DocVariantVType; // may not be set yet
      include(VOptions, dvoIsArray);
    end;
  end;
  // grow up memory if needed
  len := length(VValue);
  if VCount >= len then
  begin
    len := NextGrow(VCount);
    SetLength(VValue, len);
  end;
  result := VCount;
  inc(VCount);
  if cardinal(aIndex) < cardinal(result) then
  begin
    // reserve space for the inserted new item
    dec(result, aIndex);
    MoveFast(VValue[aIndex], VValue[aIndex + 1], result * SizeOf(variant));
    PInteger(@VValue[aIndex])^ := varEmpty; // avoid GPF
    if aName <> '' then
    begin
      if Length(VName) <> len then
        SetLength(VName, len);
      MoveFast(VName[aIndex], VName[aIndex + 1], result * SizeOf(pointer));
      PPointer(@VName[aIndex])^ := nil;
    end;
    result := aIndex;
  end;
  if aName <> '' then
  begin
    // store the object field name
    if Length(VName) <> len then
      SetLength(VName, len);
    if dvoInternNames in VOptions then
      DocVariantType.InternNames.Unique(VName[result], aName)
    else
      VName[result] := aName;
  end;
end;

{$ifdef HASITERATORS}

function TDocVariantData.GetEnumerator: TDocVariantFieldsEnumerator;
begin
  result.State.Init(pointer(Values), VCount);
  if IsObject then
  begin
    result.Name := pointer(Names);
    dec(result.Name);
  end
  else
    result.Name := nil;
end;

function TDocVariantData.Items: TDocVariantItemsEnumerator;
begin
  if IsObject then
    result{%H-}.State.Void
  else
    result.State.Init(pointer(Values), VCount);
end;

function TDocVariantData.Objects: TDocVariantObjectsEnumerator;
begin
  if IsObject then
    result{%H-}.State.Void
  else
    result.State.Init(pointer(Values), VCount);
end;

function TDocVariantData.Fields: TDocVariantFieldsEnumerator;
begin
  if IsArray then
    result{%H-}.State.Void
  else
    result := GetEnumerator;
end;

function TDocVariantData.FieldNames: TDocVariantFieldNamesEnumerator;
begin
  if IsArray or
     (VCount = 0) then
  begin
    result.Curr := nil;
    result.After := nil;
  end
  else
  begin
    result.Curr := pointer(Names);
    result.After := @Names[VCount];
    dec(result.Curr);
  end;
end;

function TDocVariantData.FieldValues: TDocVariantItemsEnumerator;
begin
  if IsArray then
    result{%H-}.State.Void
  else
    result.State.Init(pointer(Values), VCount);
end;

{$endif HASITERATORS}

procedure TDocVariantData.SetCapacity(aValue: integer);
begin
  if IsObject then
    SetLength(VName, aValue);
  SetLength(VValue, aValue);
end;

function TDocVariantData.AddValue(const aName: RawUtf8; const aValue: variant;
  aValueOwned: boolean; aIndex: integer): integer;
var
  v: PVariant;
begin
  if aName = '' then
  begin
    result := -1;
    exit;
  end;
  if dvoCheckForDuplicatedNames in VOptions then
    if GetValueIndex(aName) >= 0 then
      raise EDocVariant.CreateUtf8('AddValue: Duplicated [%] name', [aName]);
  result := InternalAdd(aName, aIndex);
  v := @VValue[result];
  if aValueOwned then
    v^ := aValue
  else
    SetVariantByValue(aValue, v^);
  if dvoInternValues in VOptions then
    InternalUniqueValue(result);
end;

function TDocVariantData.AddValue(aName: PUtf8Char; aNameLen: integer;
  const aValue: variant; aValueOwned: boolean; aIndex: integer): integer;
var
  tmp: RawUtf8;
begin
  FastSetString(tmp, aName, aNameLen);
  result := AddValue(tmp, aValue, aValueOwned, aIndex);
end;

function TDocVariantData.AddValueFromText(const aName, aValue: RawUtf8;
  DoUpdate, AllowVarDouble: boolean): integer;
var
  v: PVariant;
begin
  if aName = '' then
  begin
    result := -1;
    exit;
  end;
  result := GetValueIndex(aName);
  if not DoUpdate and
     (dvoCheckForDuplicatedNames in VOptions) and
     (result >= 0) then
    raise EDocVariant.CreateUtf8(
      'AddValueFromText: Duplicated [%] name', [aName]);
  if result < 0 then
    result := InternalAdd(aName);
  v := @VValue[result];
  VarClear(v^);
  if not GetVariantFromNotStringJson(pointer(aValue), PVarData(v)^, AllowVarDouble) then
    if dvoInternValues in VOptions then
      DocVariantType.InternValues.UniqueVariant(v^, aValue)
    else
      RawUtf8ToVariant(aValue, v^);
end;

procedure TDocVariantData.AddByPath(const aSource: TDocVariantData;
  const aPaths: array of RawUtf8; aPathDelim: AnsiChar);
var
  ndx, added: PtrInt;
  v: TVarData;
begin
  if (aSource.Count = 0) or
     (not aSource.IsObject) or
     IsArray then
    exit;
  for ndx := 0 to High(aPaths) do
  begin
    DocVariantType.Lookup(v, TVarData(aSource), pointer(aPaths[ndx]), aPathDelim);
    if cardinal(v.VType) < varNull then
      continue; // path not found
    added := InternalAdd(aPaths[ndx]);
    PVarData(@VValue[added])^ := v;
    if dvoInternValues in VOptions then
      InternalUniqueValue(added);
  end;
end;

procedure TDocVariantData.AddFrom(const aDocVariant: Variant);
var
  src: PDocVariantData;
  ndx: PtrInt;
begin
  src := _Safe(aDocVariant);
  if src^.Count = 0 then
    exit; // nothing to add
  if src^.IsArray then
    // add array items
    if IsObject then
      // types should match
      exit
    else
      for ndx := 0 to src^.Count - 1 do
        AddItem(src^.VValue[ndx])
  else
    // add object items
    if IsArray then
      // types should match
      exit
    else if dvoCheckForDuplicatedNames in VOptions then
      for ndx := 0 to src^.Count - 1 do
        AddOrUpdateValue(src^.VName[ndx], src^.VValue[ndx])
    else
      for ndx := 0 to src^.Count - 1 do
        AddValue(src^.VName[ndx], src^.VValue[ndx]);
end;

procedure TDocVariantData.AddOrUpdateFrom(const aDocVariant: Variant;
  aOnlyAddMissing: boolean);
var
  src: PDocVariantData;
  ndx: PtrInt;
begin
  src := _Safe(aDocVariant, dvObject);
  for ndx := 0 to src^.Count - 1 do
    AddOrUpdateValue(src^.VName[ndx], src^.VValue[ndx], nil, aOnlyAddMissing);
end;

function TDocVariantData.AddItem(const aValue: variant; aIndex: integer): integer;
begin
  result := InternalAdd('', aIndex);
  InternalSetValue(result, aValue);
end;

function TDocVariantData.AddItem(const aValue: TDocVariantData; aIndex: integer): integer;
begin
  result := InternalAdd('', aIndex);
  InternalSetValue(result, variant(aValue));
end;

function TDocVariantData.AddItemFromText(const aValue: RawUtf8;
  AllowVarDouble: boolean; aIndex: integer): integer;
var
  v: PVariant;
begin
  result := InternalAdd('', aIndex);
  v := @VValue[result];
  if not GetVariantFromNotStringJson(pointer(aValue), PVarData(v)^, AllowVarDouble) then
    if dvoInternValues in VOptions then
      DocVariantType.InternValues.UniqueVariant(v^, aValue)
    else
      RawUtf8ToVariant(aValue, v^);
end;

function TDocVariantData.AddItemText(
  const aValue: RawUtf8; aIndex: integer): integer;
begin
  result := InternalAdd('', aIndex);
  if dvoInternValues in VOptions then
    DocVariantType.InternValues.UniqueVariant(VValue[result], aValue)
  else
    RawUtf8ToVariant(aValue, VValue[result]);
end;

procedure TDocVariantData.AddItems(const aValue: array of const);
var
  ndx, added: PtrInt;
begin
  for ndx := 0 to high(aValue) do
  begin
    added := InternalAdd('');
    VarRecToVariant(aValue[ndx], VValue[added]);
    if dvoInternValues in VOptions then
      InternalUniqueValue(added);
  end;
end;

procedure TDocVariantData.AddObject(const aNameValuePairs: array of const;
  const aName: RawUtf8);
var
  added: PtrInt;
  obj: PDocVariantData;
begin
  if (aName <> '') and
     (dvoCheckForDuplicatedNames in VOptions) then
    if GetValueIndex(aName) >= 0 then
      raise EDocVariant.CreateUtf8('AddObject: Duplicated [%] name', [aName]);
  added := InternalAdd(aName);
  obj := @VValue[added];
  if PInteger(obj)^ = 0 then // most common case is adding a new value
    obj^.InitClone(self)     // same options than owner document
  else if (obj^.VType <> VType) or
          not obj^.IsObject then
    raise EDocVariant.CreateUtf8('AddObject: wrong existing [%]', [aName]);
  obj^.AddNameValuesToObject(aNameValuePairs);
  if dvoInternValues in VOptions then
    InternalUniqueValue(added);
end;

function TDocVariantData.GetObjectProp(const aName: RawUtf8;
  out aFound: PVariant): boolean;
var
  ndx: PtrInt;
begin
  result := false;
  if (VCount = 0) or
     (aName = '') or
     not IsObject then
    exit;
  ndx := FindNonVoid[IsCaseSensitive](
        pointer(VName), pointer(aName), length(aName), VCount);
  if ndx < 0 then
    exit;
  aFound := @VValue[ndx];
  result  := true;
end;

function TDocVariantData.SearchItemByProp(const aPropName, aPropValue: RawUtf8;
  aPropValueCaseSensitive: boolean): integer;
var
  v: PVariant;
begin
  if IsObject then
  begin
    result := GetValueIndex(aPropName);
    if (result >= 0) and
       VariantEquals(VValue[result], aPropValue, aPropValueCaseSensitive) then
      exit;
  end
  else if IsArray then
    for result := 0 to VCount - 1 do
      if _Safe(VValue[result])^.GetObjectProp(aPropName, v) and
         VariantEquals({%H-}v^, aPropValue, aPropValueCaseSensitive) then
        exit;
  result := -1;
end;

function TDocVariantData.SearchItemByProp(const aPropNameFmt: RawUtf8;
  const aPropNameArgs: array of const; const aPropValue: RawUtf8;
  aPropValueCaseSensitive: boolean): integer;
var
  name: RawUtf8;
begin
  FormatUtf8(aPropNameFmt, aPropNameArgs, name);
  result := SearchItemByProp(name, aPropValue, aPropValueCaseSensitive);
end;

function TDocVariantData.SearchItemByValue(const aValue: Variant;
  CaseInsensitive: boolean; StartIndex: PtrInt): PtrInt;
var
  v: PVarData;
begin
  v := @VValue[StartIndex];
  for result := StartIndex to VCount - 1 do
    if FastVarDataComp(v, @aValue, CaseInsensitive) = 0 then
      exit
    else
      inc(v);
  result := -1;
end;

type
  {$ifdef USERECORDWITHMETHODS}
  TQuickSortDocVariant = record
  {$else}
  TQuickSortDocVariant = object
  {$endif USERECORDWITHMETHODS}
  public
    names: PPointerArray;
    values: PVariantArray;
    nameCompare: TUtf8Compare;
    valueCompare: TVariantCompare;
    valueComparer: TVariantComparer;
    reversed: PtrInt;
    procedure SortByName(L, R: PtrInt);
    procedure SortByValue(L, R: PtrInt);
  end;

procedure TQuickSortDocVariant.SortByName(L, R: PtrInt);
var
  I, J, P: PtrInt;
  pivot: pointer;
begin
  if L < R then
    repeat
      I := L;
      J := R;
      P := (L + R) shr 1;
      repeat
        pivot := names[P];
        while nameCompare(names[I], pivot) * reversed < 0 do
          inc(I);
        while nameCompare(names[J], pivot) * reversed > 0 do
          dec(J);
        if I <= J then
        begin
          if I <> J then
          begin
            ExchgPointer(@names[I], @names[J]);
            ExchgVariant(@values[I], @values[J]);
          end;
          if P = I then
            P := J
          else if P = J then
            P := I;
          inc(I);
          dec(J);
        end;
      until I > J;
      if J - L < R - I then
      begin
        // use recursion only for smaller range
        if L < J then
          SortByName(L, J);
        L := I;
      end
      else
      begin
        if I < R then
          SortByName(I, R);
        R := J;
      end;
    until L >= R;
end;

procedure TQuickSortDocVariant.SortByValue(L, R: PtrInt);
var
  I, J, P: PtrInt;
  pivot: PVariant;
begin
  if L < R then
    repeat
      I := L;
      J := R;
      P := (L + R) shr 1;
      repeat
        pivot := @values[P];
        if Assigned(valueCompare) then
        begin // called from SortByValue
          while valueCompare(values[I], pivot^) * reversed < 0 do
            inc(I);
          while valueCompare(values[J], pivot^) * reversed > 0 do
            dec(J);
        end
        else
        begin // called from SortByRow
          while valueComparer(values[I], pivot^) * reversed < 0 do
            inc(I);
          while valueComparer(values[J], pivot^) * reversed > 0 do
            dec(J);
        end;
        if I <= J then
        begin
          if I <> J then
          begin
            if names <> nil then
              ExchgPointer(@names[I], @names[J]);
            ExchgVariant(@values[I], @values[J]);
          end;
          if P = I then
            P := J
          else if P = J then
            P := I;
          inc(I);
          dec(J);
        end;
      until I > J;
      if J - L < R - I then
      begin
        // use recursion only for smaller range
        if L < J then
          SortByValue(L, J);
        L := I;
      end
      else
      begin
        if I < R then
          SortByValue(I, R);
        R := J;
      end;
    until L >= R;
end;

procedure TDocVariantData.SortByName(
  SortCompare: TUtf8Compare; SortCompareReversed: boolean);
var
  qs: TQuickSortDocVariant;
begin
  if (not IsObject) or
     (VCount <= 0) then
    exit;
  if Assigned(SortCompare) then
    qs.nameCompare := SortCompare
  else
    qs.nameCompare := @StrIComp;
  qs.names := pointer(VName);
  qs.values := pointer(VValue);
  if SortCompareReversed then
    qs.reversed := -1
  else
    qs.reversed := 1;
  qs.SortByName(0, VCount - 1);
end;

procedure TDocVariantData.SortByValue(SortCompare: TVariantCompare;
  SortCompareReversed: boolean);
var
  qs: TQuickSortDocVariant;
begin
  if VCount <= 0 then
    exit;
  if Assigned(SortCompare) then
    qs.valueCompare := SortCompare
  else
    qs.valueCompare := @VariantCompare;
  qs.valueComparer := nil;
  qs.names := pointer(VName);
  qs.values := pointer(VValue);
  if SortCompareReversed then
    qs.reversed := -1
  else
    qs.reversed := 1;
  qs.SortByValue(0, VCount - 1);
end;

procedure TDocVariantData.SortByRow(const SortComparer: TVariantComparer;
  SortComparerReversed: boolean);
var
  qs: TQuickSortDocVariant;
begin
  if (VCount <= 0) or
     (not Assigned(SortComparer)) then
    exit;
  qs.valueCompare := nil;
  qs.valueComparer := SortComparer;
  qs.names := pointer(VName);
  qs.values := pointer(VValue);
  if SortComparerReversed then
    qs.reversed := -1
  else
    qs.reversed := 1;
  qs.SortByValue(0, VCount - 1);
end;

type
  TQuickSortByFieldLookup = array[0..3] of PVariant;
  PQuickSortByFieldLookup = ^TQuickSortByFieldLookup;

  {$ifdef USERECORDWITHMETHODS}
  TQuickSortDocVariantValuesByField = record
  {$else}
  TQuickSortDocVariantValuesByField = object
  {$endif USERECORDWITHMETHODS}
  public
    Lookup: array of TQuickSortByFieldLookup;
    Compare: TVariantCompare;
    CompareField: TVariantCompareField;
    Fields: PRawUtf8Array;
    P: PtrInt;
    Pivot: PQuickSortByFieldLookup;
    Doc: PDocVariantData;
    TempExch: TQuickSortByFieldLookup;
    Reverse: boolean;
    Depth: integer; // = high(Lookup)
    procedure Init(const aPropNames: array of RawUtf8;
      aNameSortedCompare: TUtf8Compare);
    function DoComp(Value: PQuickSortByFieldLookup): PtrInt;
      {$ifndef CPUX86} inline; {$endif}
    procedure Sort(L, R: PtrInt);
  end;

procedure TQuickSortDocVariantValuesByField.Init(
  const aPropNames: array of RawUtf8; aNameSortedCompare: TUtf8Compare);
var
  namecomp: TUtf8Compare;
  v: pointer;
  row, f: PtrInt;
  rowdata: PDocVariantData;
  ndx: integer;
begin
  Depth := high(aPropNames);
  if (Depth < 0) or
     (Depth > high(TQuickSortByFieldLookup)) then
    raise EDocVariant.CreateUtf8('TDocVariantData.SortByFields(%)', [Depth]);
  // resolve GetPVariantByName(aPropNames) once into Lookup[]
  SetLength(Lookup, Doc^.VCount);
  if Assigned(aNameSortedCompare) then // just like GetVarData() searches names
    namecomp := aNameSortedCompare
  else
    namecomp := StrCompByCase[not Doc^.IsCaseSensitive];
  for f := 0 to Depth do
  begin
    if aPropNames[f] = '' then
      raise EDocVariant.CreateUtf8('TDocVariantData.SortByFields(%=void)', [f]);
    ndx := -1;
    for row := 0 to Doc^.VCount - 1 do
    begin
      rowdata := _Safe(Doc^.VValue[row]);
      if (cardinal(ndx) < cardinal(rowdata^.VCount)) and
         (namecomp(pointer(rowdata^.VName[ndx]), pointer(aPropNames[f])) = 0) then
        v := @rowdata^.VValue[ndx] // get the value at the (likely) same position
      else
      begin
        v := rowdata^.GetVarData(aPropNames[f], aNameSortedCompare, @ndx);
        if v = nil then
          v := @NullVarData;
      end;
      Lookup[row, f] := v;
    end;
  end;
end;

function TQuickSortDocVariantValuesByField.DoComp(
  Value: PQuickSortByFieldLookup): PtrInt;
begin
  if Assigned(Compare) then
  begin
    result := Compare(Value[0]^, Pivot[0]^);
    if (result = 0) and
       (depth > 0) then
    begin
      result := Compare(Value[1]^, Pivot[1]^);
      if (result = 0) and
         (depth > 1) then
      begin
        result := Compare(Value[2]^, Pivot[2]^);
        if (result = 0) and
           (depth > 2) then
         result := Compare(Value[3]^, Pivot[3]^);
      end;
    end;
  end
  else
  begin
    result := CompareField(Fields[0], Value[0]^, Pivot[0]^);
    if (result = 0) and
       (depth > 0) then
    begin
      result := CompareField(Fields[1], Value[1]^, Pivot[1]^);
      if (result = 0) and
         (depth > 1) then
      begin
        result := CompareField(Fields[2], Value[2]^, Pivot[2]^);
        if (result = 0) and
           (depth > 2) then
         result := CompareField(Fields[3], Value[3]^, Pivot[3]^);
      end;
    end;
  end;
  if Reverse then
    result := -result;
end;

procedure TQuickSortDocVariantValuesByField.Sort(L, R: PtrInt);
var
  I, J: PtrInt;
begin
  if L < R then
    repeat
      I := L;
      J := R;
      P := (L + R) shr 1;
      repeat
        Pivot := @Lookup[P];
        while DoComp(@Lookup[I]) < 0 do
          inc(I);
        while DoComp(@Lookup[J]) > 0 do
          dec(J);
        if I <= J then
        begin
          if I <> J then
          begin
            if Doc.VName <> nil then
              ExchgPointer(@Doc.VName[I], @Doc.VName[J]);
            ExchgVariant(@Doc.VValue[I], @Doc.VValue[J]);
            ExchgPointers(@Lookup[I], @Lookup[J], Depth + 1);
          end;
          if P = I then
            P := J
          else if P = J then
            P := I;
          inc(I);
          dec(J);
        end;
      until I > J;
      if J - L < R - I then
      begin
        // use recursion only for smaller range
        if L < J then
          Sort(L, J);
        L := I;
      end
      else
      begin
        if I < R then
          Sort(I, R);
        R := J;
      end;
    until L >= R;
end;

procedure TDocVariantData.SortArrayByField(const aItemPropName: RawUtf8;
  aValueCompare: TVariantCompare; aValueCompareReverse: boolean;
  aNameSortedCompare: TUtf8Compare);
var
  QS: TQuickSortDocVariantValuesByField;
begin
  if (VCount <= 0) or
     (aItemPropName = '') or
     not IsArray then
    exit;
  if not Assigned(aValueCompare) then
    aValueCompare := VariantCompare;
  QS.Compare := aValueCompare;
  QS.Doc := @self;
  QS.Init([aItemPropName], aNameSortedCompare);
  QS.Reverse := aValueCompareReverse;
  QS.Sort(0, VCount - 1);
end;

procedure TDocVariantData.SortArrayByFields(
  const aItemPropNames: array of RawUtf8; aValueCompare: TVariantCompare;
  const aValueCompareField: TVariantCompareField;
  aValueCompareReverse: boolean; aNameSortedCompare: TUtf8Compare);
var
  QS: TQuickSortDocVariantValuesByField;
begin
  if (VCount <= 0) or
     not IsArray then
    exit;
  if Assigned(aValueCompareField) then
  begin
    QS.Compare := nil;
    QS.Fields := @aItemPropNames[0];
    QS.CompareField := aValueCompareField;
  end
  else if Assigned(aValueCompare) then
      QS.Compare := aValueCompare
    else
      QS.Compare := VariantCompare;
  QS.Doc := @self;
  QS.Init(aItemPropNames, aNameSortedCompare);
  QS.Reverse := aValueCompareReverse;
  QS.Sort(0, VCount - 1);
end;

procedure TDocVariantData.Reverse;
begin
  if VCount <= 0 then
    exit;
  if VName <> nil then
    DynArray(TypeInfo(TRawUtf8DynArray), VName, @VCount).Reverse;
  DynArray(TypeInfo(TVariantDynArray), VValue, @VCount).Reverse;
end;

function TDocVariantData.Reduce(const aPropNames: array of RawUtf8;
  aCaseSensitive, aDoNotAddVoidProp: boolean): variant;
begin
  VarClear(result{%H-});
  Reduce(
    aPropNames, aCaseSensitive, PDocVariantData(@result)^, aDoNotAddVoidProp);
end;

procedure TDocVariantData.Reduce(const aPropNames: array of RawUtf8;
  aCaseSensitive: boolean; var result: TDocVariantData;
  aDoNotAddVoidProp: boolean);
var
  ndx, j: PtrInt;
  reduced: TDocVariantData;
begin
  TVarData(result) := DV_FAST[dvUndefined];
  if (VCount = 0) or
     (high(aPropNames) < 0) then
    exit;
  if IsObject then
    for j := 0 to high(aPropNames) do
    begin
      ndx := FindNonVoid[aCaseSensitive](
        pointer(VName), pointer(aPropNames[j]), length(aPropNames[j]), VCount);
      if ndx >= 0 then
        if not aDoNotAddVoidProp or
           not VarIsVoid(VValue[ndx]) then
          result.AddValue(VName[ndx], VValue[ndx]);
    end
  else if IsArray then
    for ndx := 0 to VCount - 1 do
    begin
      _Safe(VValue[ndx])^.Reduce(
        aPropNames, aCaseSensitive, reduced, aDoNotAddVoidProp);
      if not reduced.IsObject then
        continue;
      result.AddItem(variant(reduced));
      reduced.Clear;
    end;
end;

function TDocVariantData.ReduceAsArray(const aPropName: RawUtf8;
  const OnReduce: TOnReducePerItem): variant;
begin
  VarClear(result{%H-});
  ReduceAsArray(aPropName, PDocVariantData(@result)^, OnReduce);
end;

procedure TDocVariantData.ReduceAsArray(const aPropName: RawUtf8;
  var result: TDocVariantData; const OnReduce: TOnReducePerItem);
var
  ndx: PtrInt;
  item: PDocVariantData;
  v: PVariant;
begin
  TVarData(result) := DV_FAST[dvArray];
  if (VCount <> 0) and
     (aPropName <> '') and
     IsArray then
    for ndx := 0 to VCount - 1 do
      if _Safe(VValue[ndx], item) and
         {%H-}item^.GetObjectProp(aPropName, v) then
        if (not Assigned(OnReduce)) or
           OnReduce(item) then
          result.AddItem(v^);
end;

function TDocVariantData.ReduceAsArray(const aPropName: RawUtf8;
  const OnReduce: TOnReducePerValue): variant;
begin
  VarClear(result{%H-});
  ReduceAsArray(aPropName, PDocVariantData(@result)^, OnReduce);
end;

procedure TDocVariantData.ReduceAsArray(const aPropName: RawUtf8;
  var result: TDocVariantData; const OnReduce: TOnReducePerValue);
var
  ndx: PtrInt;
  v: PVariant;
begin
  TVarData(result) := DV_FAST[dvArray];
  if (VCount <> 0) and
     (aPropName <> '') and
     IsArray then
    for ndx := 0 to VCount - 1 do
      if _Safe(VValue[ndx])^.GetObjectProp(aPropName, v) then
        if (not Assigned(OnReduce)) or
           OnReduce(v^) then
          result.AddItem(v^);
end;

function NotIn(a, v: PVarData; n: integer; caseins: boolean): boolean;
begin
  result := false;
  if n <> 0 then
    repeat
      if FastVarDataComp(a, v, caseins) = 0 then
        exit;
      inc(a);
      dec(n);
    until n = 0;
  result := true;
end;

function TDocVariantData.ReduceAsVariantArray(const aPropName: RawUtf8;
  aDuplicates: TSearchDuplicate): TVariantDynArray;
var
  n, ndx: PtrInt;
  v: PVariant;
begin
  n := 0;
  result := nil;
  if (VCount <> 0) and
     (aPropName <> '') and
     IsArray then
  for ndx := 0 to VCount - 1 do
    if _Safe(VValue[ndx])^.GetObjectProp(aPropName, v) then
      if (aDuplicates = sdNone) or
         NotIn(pointer(result), pointer(v), n, aDuplicates = sdCaseInsensitive) then
      begin
        if length(result) = n then
          SetLength(result, NextGrow(n));
        SetVariantByValue(PVariant(v)^, result[n]);
        inc(n);
      end;
  if n <> 0 then
    DynArrayFakeLength(result, n);
end;

function TDocVariantData.Rename(
  const aFromPropName, aToPropName: TRawUtf8DynArray): integer;
var
  n, prop, ndx: PtrInt;
begin
  result := 0;
  n := length(aFromPropName);
  if length(aToPropName) = n then
    for prop := 0 to n - 1 do
    begin
      ndx := GetValueIndex(aFromPropName[prop]);
      if ndx >= 0 then
      begin
        VName[ndx] := aToPropName[prop];
        inc(result);
      end;
    end;
end;

function TDocVariantData.GetNames: TRawUtf8DynArray;
begin
  if IsObject and
     (VCount > 0) then
  begin
    DynArrayFakeLength(VName, VCount);
    DynArrayFakeLength(VValue, VCount);
    result := VName; // truncate with no memory (re)allocation
  end
  else
    result := nil;
end;

function TDocVariantData.FlattenAsNestedObject(
  const aObjectPropName: RawUtf8): boolean;
var
  ndx, len: PtrInt;
  Up: array[byte] of AnsiChar;
  nested: TDocVariantData;
begin
  // {"p.a1":5,"p.a2":"dfasdfa"} -> {"p":{"a1":5,"a2":"dfasdfa"}}
  result := false;
  if (VCount = 0) or
     (aObjectPropName = '') or
     (not IsObject) then
    exit;
  PWord(UpperCopy255(Up{%H-}, aObjectPropName))^ := ord('.'); // e.g. 'P.'
  for ndx := 0 to Count - 1 do
    if not IdemPChar(pointer(VName[ndx]), Up) then
      exit; // all fields should match "p.####"
  len := length(aObjectPropName) + 1;
  for ndx := 0 to Count - 1 do
    system.delete(VName[ndx], 1, len);
  nested := self;
  ClearFast;
  InitObject([aObjectPropName, variant(nested)]);
  result := true;
end;

function TDocVariantData.Delete(Index: PtrInt): boolean;
var
  n: PtrInt;
begin
  if cardinal(Index) >= cardinal(VCount) then
    result := false
  else
  begin
    dec(VCount);
    if VName <> nil then
    begin
      if PDACnt(PAnsiChar(pointer(VName)) - _DACNT)^ > 1 then
        VName := copy(VName); // make unique
      VName[Index] := '';
    end;
    if PDACnt(PAnsiChar(pointer(VValue)) - _DACNT)^ > 1 then
      VValue := copy(VValue); // make unique
    VarClear(VValue[Index]);
    n := VCount - Index;
    if n <> 0 then
    begin
      if VName <> nil then
      begin
        MoveFast(VName[Index + 1], VName[Index], n * SizeOf(pointer));
        PtrUInt(VName[VCount]) := 0; // avoid GPF
      end;
      MoveFast(VValue[Index + 1], VValue[Index], n * SizeOf(variant));
      TRttiVarData(VValue[VCount]).VType := varEmpty; // avoid GPF
    end;
    result := true;
  end;
end;

function TDocVariantData.Delete(const aName: RawUtf8): boolean;
begin
  result := Delete(GetValueIndex(aName));
end;

function TDocVariantData.Delete(const aNames: array of RawUtf8): integer;
var
  n: PtrInt;
begin
  result := 0;
  for n := 0 to high(aNames) do
    inc(result, ord(Delete(aNames[n])));
end;

function TDocVariantData.InternalNextPath(
  var aCsv: PUtf8Char; aName: PShortString; aPathDelim: AnsiChar): PtrInt;
begin
  GetNextItemShortString(aCsv, aName, aPathDelim);
  if (aName^[0] in [#0, #254]) or
     (VCount = 0) then
    result := -1
  else
    result := FindNonVoid[IsCaseSensitive](
      pointer(VName), @aName^[1], ord(aName^[0]), VCount);
end;

procedure TDocVariantData.InternalNotFound(var Dest: variant; aName: PUtf8Char);
begin
  if dvoReturnNullForUnknownProperty in VOptions then
    SetVariantNull(Dest)
  else
    raise EDocVariant.CreateUtf8('[%] property not found', [aName])
end;

procedure TDocVariantData.InternalNotFound(var Dest: variant; aIndex: integer);
begin
  if dvoReturnNullForUnknownProperty in VOptions then
    SetVariantNull(Dest)
  else
    raise EDocVariant.CreateUtf8('Out of range [%] (count=%)', [aIndex, VCount]);
end;

function TDocVariantData.InternalNotFound(aName: PUtf8Char): PVariant;
begin
  if dvoReturnNullForUnknownProperty in VOptions then
    result := @DocVariantDataFake
  else
    raise EDocVariant.CreateUtf8('[%] property not found', [aName])
end;

function TDocVariantData.InternalNotFound(aIndex: integer): PDocVariantData;
begin
  if dvoReturnNullForUnknownProperty in VOptions then
    result := @DocVariantDataFake
  else
    raise EDocVariant.CreateUtf8('Out of range [%] (count=%)', [aIndex, VCount]);
end;

function TDocVariantData.DeleteByPath(
  const aPath: RawUtf8; aPathDelim: AnsiChar): boolean;
var
  csv: PUtf8Char;
  v: PDocVariantData;
  ndx: PtrInt;
  n: ShortString;
begin
  result := false;
  if IsArray then
    exit;
  csv := pointer(aPath);
  v := @self;
  repeat
    ndx := v^.InternalNextPath(csv, @n, aPathDelim);
    if csv = nil then
    begin
      // we reached the last item of the path, which is to be deleted
      result := v^.Delete(ndx);
      exit;
    end;
  until (ndx < 0) or
       not _SafeObject(v^.VValue[ndx], v);
end;

function TDocVariantData.DeleteByProp(const aPropName, aPropValue: RawUtf8;
  aPropValueCaseSensitive: boolean): boolean;
begin
  result := Delete(SearchItemByProp(aPropName, aPropValue, aPropValueCaseSensitive));
end;

function TDocVariantData.DeleteByValue(const aValue: Variant;
  CaseInsensitive: boolean): integer;
var
  ndx: PtrInt;
begin
  result := 0;
  if VarIsEmptyOrNull(aValue) then
  begin
    for ndx := VCount - 1 downto 0 do
      if VarDataIsEmptyOrNull(@VValue[ndx]) then
      begin
        Delete(ndx);
        inc(result);
      end;
  end
  else
    for ndx := VCount - 1 downto 0 do
      if FastVarDataComp(@VValue[ndx], @aValue, CaseInsensitive) = 0 then
      begin
        Delete(ndx);
        inc(result);
      end;
end;

function TDocVariantData.DeleteByStartName(
  aStartName: PUtf8Char; aStartNameLen: integer): integer;
var
  ndx: PtrInt;
  upname: array[byte] of AnsiChar;
begin
  result := 0;
  if aStartNameLen = 0 then
    aStartNameLen := StrLen(aStartName);
  if (VCount = 0) or
     (not IsObject) or
     (aStartNameLen = 0) then
    exit;
  UpperCopy255Buf(upname{%H-}, aStartName, aStartNameLen)^ := #0;
  for ndx := Count - 1 downto 0 do
    if IdemPChar(pointer(names[ndx]), upname) then
    begin
      Delete(ndx);
      inc(result);
    end;
end;

function TDocVariantData.IsVoid: boolean;
begin
  result := (cardinal(VType) <> DocVariantVType) or
            (VCount = 0);
end;

function TDocVariantData.GetValueIndex(aName: PUtf8Char; aNameLen: PtrInt;
  aCaseSensitive: boolean): integer;
var
  err: integer;
begin
  if (cardinal(VType) = DocVariantVType) and
     (aNameLen > 0) and
     (aName <> nil) and
     (VCount > 0) then
    if IsArray then
    begin
      // try index integer as text, for lookup in array document
      result := GetInteger(aName, err);
      if (err <> 0) or
         (cardinal(result) >= cardinal(VCount)) then
        result := -1;
    end
    else
      // O(n) lookup for name -> efficient brute force sub-functions
      result := FindNonVoid[IsCaseSensitive](
        pointer(VName), aName, aNameLen, VCount)
  else
    result := -1;
end;

function TDocVariantData.GetValueOrRaiseException(
  const aName: RawUtf8): variant;
begin
  RetrieveValueOrRaiseException(
    pointer(aName), length(aName), IsCaseSensitive, result, false);
end;

function TDocVariantData.GetValueOrDefault(const aName: RawUtf8;
  const aDefault: variant): variant;
var
  v: PVariant;
begin
  if (cardinal(VType) <> DocVariantVType) or
     not GetObjectProp(aName, v{%H-}) then
    result := aDefault
  else
    SetVariantByValue(v^, result);
end;

function TDocVariantData.GetValueOrNull(const aName: RawUtf8): variant;
var
  v: PVariant;
begin
  if (cardinal(VType) <> DocVariantVType) or
     not GetObjectProp(aName, v{%H-}) then
    SetVariantNull(result{%H-})
  else
    SetVariantByValue(v^, result);
end;

function TDocVariantData.GetValueOrEmpty(const aName: RawUtf8): variant;
var
  v: PVariant;
begin
  if (cardinal(VType) <> DocVariantVType) or
     not GetObjectProp(aName, v{%H-}) then
   VarClear(result{%H-})
  else
    SetVariantByValue(v^, result);
end;

function TDocVariantData.GetAsBoolean(const aName: RawUtf8; out aValue: boolean;
  aSortedCompare: TUtf8Compare): boolean;
var
  found: PVarData;
begin
  found := GetVarData(aName, aSortedCompare);
  if found = nil then
    result := false
  else
    result := VariantToBoolean(PVariant(found)^, aValue)
end;

function TDocVariantData.GetAsInteger(const aName: RawUtf8; out aValue: integer;
  aSortedCompare: TUtf8Compare): boolean;
var
  found: PVarData;
begin
  found := GetVarData(aName, aSortedCompare);
  if found = nil then
    result := false
  else
    result := VariantToInteger(PVariant(found)^, aValue);
end;

function TDocVariantData.GetAsInt64(const aName: RawUtf8; out aValue: Int64;
  aSortedCompare: TUtf8Compare): boolean;
var
  found: PVarData;
begin
  found := GetVarData(aName, aSortedCompare);
  if found = nil then
    result := false
  else
    result := VariantToInt64(PVariant(found)^, aValue)
end;

function TDocVariantData.GetAsDouble(const aName: RawUtf8; out aValue: double;
  aSortedCompare: TUtf8Compare): boolean;
var
  found: PVarData;
begin
  found := GetVarData(aName, aSortedCompare);
  if found = nil then
    result := false
  else
    result := VariantToDouble(PVariant(found)^, aValue);
end;

function TDocVariantData.GetAsRawUtf8(const aName: RawUtf8; out aValue: RawUtf8;
  aSortedCompare: TUtf8Compare): boolean;
var
  found: PVarData;
  wasString: boolean;
begin
  found := GetVarData(aName, aSortedCompare);
  if found = nil then
    result := false
  else
  begin
    if cardinal(found^.VType) > varNull then
      // avoid default VariantToUtf8(null)='null'
      VariantToUtf8(PVariant(found)^, aValue, wasString);
    result := true;
  end;
end;

function TDocVariantData.GetValueEnumerate(const aName: RawUtf8;
  aTypeInfo: PRttiInfo; out aValue; aDeleteFoundEntry: boolean): boolean;
var
  text: RawUtf8;
  ndx, ord: integer;
begin
  result := false;
  ndx := GetValueIndex(aName);
  if (ndx < 0) or
     not VariantToText(Values[ndx], text) then
    exit;
  ord := GetEnumNameValue(aTypeInfo, text, true);
  if ord < 0 then
    exit;
  byte(aValue) := ord;
  if aDeleteFoundEntry then
    Delete(ndx);
  result := true;
end;

function TDocVariantData.GetAsDocVariant(const aName: RawUtf8;
  out aValue: PDocVariantData; aSortedCompare: TUtf8Compare): boolean;
var
  found: PVarData;
begin
  found := GetVarData(aName, aSortedCompare);
  result := (found <> nil) and
            _Safe(PVariant(found)^, aValue);
end;

function TDocVariantData.GetAsArray(const aName: RawUtf8;
  out aArray: PDocVariantData; aSortedCompare: TUtf8Compare): boolean;
begin
  result := GetAsDocVariant(aName, aArray, aSortedCompare) and
            aArray^.IsArray and
            (aArray^.Count > 0);
end;

function TDocVariantData.GetAsObject(const aName: RawUtf8;
  out aObject: PDocVariantData; aSortedCompare: TUtf8Compare): boolean;
begin
  result := GetAsDocVariant(aName, aObject, aSortedCompare) and
            aObject^.IsObject and
            (aObject^.Count > 0);
end;

function TDocVariantData.GetAsDocVariantSafe(const aName: RawUtf8;
  aSortedCompare: TUtf8Compare): PDocVariantData;
var
  found: PVarData;
begin
  found := GetVarData(aName, aSortedCompare);
  if found = nil then
    result := @DocVariantDataFake
  else
    result := _Safe(PVariant(found)^);
end;

function TDocVariantData.GetAsPVariant(const aName: RawUtf8;
  out aValue: PVariant; aSortedCompare: TUtf8Compare): boolean;
begin
  aValue := pointer(GetVarData(aName, aSortedCompare));
  result := aValue <> nil;
end;

function TDocVariantData.GetAsPVariant(
  aName: PUtf8Char; aNameLen: PtrInt): PVariant;
var
  ndx: PtrInt;
begin
  ndx := GetValueIndex(aName, aNameLen, IsCaseSensitive);
  if ndx >= 0 then
    result := @VValue[ndx]
  else
    result := nil;
end;

function TDocVariantData.GetVarData(const aName: RawUtf8;
  aSortedCompare: TUtf8Compare; aFoundIndex: PInteger): PVarData;
var
  ndx: PtrInt;
begin
  if (cardinal(VType) <> DocVariantVType) or
     (not IsObject) or
     (VCount = 0) or
     (aName = '') then
  begin
    result := nil;
    if aFoundIndex <> nil then
      aFoundIndex^ := -1;
  end
  else
  begin
    if Assigned(aSortedCompare) then
      if @aSortedCompare = @StrComp then
        // use our branchless asm for StrComp()
        ndx := FastFindPUtf8CharSorted(
          pointer(VName), VCount - 1, pointer(aName))
      else
        ndx := FastFindPUtf8CharSorted(
          pointer(VName), VCount - 1, pointer(aName), aSortedCompare)
    else
      ndx := FindNonVoid[IsCaseSensitive](
        pointer(VName), pointer(aName), length(aName), VCount);
    if aFoundIndex <> nil then
      aFoundIndex^ := ndx;
    if ndx >= 0 then
      result := @VValue[ndx]
    else
      result := nil;
  end;
end;

function TDocVariantData.GetVarData(const aName: RawUtf8; var aValue: TVarData;
  aSortedCompare: TUtf8Compare): boolean;
var
  found: PVarData;
begin
  found := GetVarData(aName, aSortedCompare);
  if found = nil then
    result := false
  else
  begin
    aValue := found^;
    result := true;
  end;
end;

function TDocVariantData.GetValueByPath(
  const aPath: RawUtf8; aPathDelim: AnsiChar): variant;
var
  Dest: TVarData;
begin
  VarClear(result{%H-});
  if (cardinal(VType) <> DocVariantVType) or
     (not IsObject) then
    exit;
  DocVariantType.Lookup(Dest, TVarData(self), pointer(aPath), aPathDelim);
  if cardinal(Dest.VType) >= varNull then
    result := variant(Dest); // copy
end;

function TDocVariantData.GetValueByPath(const aPath: RawUtf8;
  out aValue: variant; aPathDelim: AnsiChar): boolean;
var
  Dest: TVarData;
begin
  result := false;
  if (cardinal(VType) <> DocVariantVType) or
     (not IsObject) then
    exit;
  DocVariantType.Lookup(Dest, TVarData(self), pointer(aPath), aPathDelim);
  if Dest.VType = varEmpty then
    exit;
  aValue := variant(Dest); // copy
  result := true;
end;

function TDocVariantData.GetPVariantByPath(
  const aPath: RawUtf8; aPathDelim: AnsiChar): PVariant;
var
  path: PUtf8Char;
  ndx: PtrInt;
  n: ShortString;
begin
  if (cardinal(VType) <> DocVariantVType) or
     (aPath = '') or
     (not IsObject) or
     (VCount = 0) then
  begin
    result := nil;
    exit;
  end;
  result := @self;
  path := pointer(aPath);
  repeat
    with _Safe(result^)^ do
    begin
      ndx := InternalNextPath(path, @n, aPathDelim);
      result := nil;
      if ndx < 0 then
        exit;
      result := @VValue[ndx];
    end;
  until path = nil;
  // if we reached here, we have result=found item
end;

function TDocVariantData.GetVariantByPath(const aNameOrPath: RawUtf8): Variant;
var
  v: PVariant;
begin
  v := GetPVariantByPath(aNameOrPath, '.');
  if v <> nil then
    SetVariantByValue(v^, result)
  else
    InternalNotFound(result, pointer(aNameOrPath));
end;

function TDocVariantData.GetDocVariantByPath(const aPath: RawUtf8;
  out aValue: PDocVariantData; aPathDelim: AnsiChar): boolean;
var
  v: PVariant;
begin
  v := GetPVariantByPath(aPath, aPathDelim);
  result := (v <> nil) and
            _Safe(v^, aValue);
end;

function TDocVariantData.GetValueByPath(
  const aDocVariantPath: array of RawUtf8): variant;
var
  found, res: PVarData;
  vt: cardinal;
  ndx: integer;
begin
  VarClear(result{%H-});
  if (cardinal(VType) <> DocVariantVType) or
     (not IsObject) or
     (high(aDocVariantPath) < 0) then
    exit;
  found := @self;
  ndx := 0;
  repeat
    found := PDocVariantData(found).GetVarData(aDocVariantPath[ndx]);
    if found = nil then
      exit;
    if ndx = high(aDocVariantPath) then
      break; // we found the item!
    inc(ndx);
    // if we reached here, we should try for the next scope within Dest
    repeat
      vt := found^.VType;
      if vt <> varVariantByRef then
        break;
      found := found^.VPointer;
    until false;
    if vt = VType then
      continue;
    exit;
  until false;
  res := found;
  while cardinal(res^.VType) = varVariantByRef do
    res := res^.VPointer;
  if (cardinal(res^.VType) = VType) and
     (PDocVariantData(res)^.VCount = 0) then
    // return void TDocVariant as null
    TVarData(result).VType := varNull
  else
    // copy found value
    result := PVariant(found)^;
end;

function TDocVariantData.GetItemByProp(const aPropName, aPropValue: RawUtf8;
  aPropValueCaseSensitive: boolean; var Dest: variant; DestByRef: boolean): boolean;
var
  ndx: integer;
begin
  result := false;
  if not IsArray then
    exit;
  ndx := SearchItemByProp(aPropName, aPropValue, aPropValueCaseSensitive);
  if ndx < 0 then
    exit;
  RetrieveValueOrRaiseException(ndx, Dest, DestByRef);
  result := true;
end;

function TDocVariantData.GetDocVariantByProp(
  const aPropName, aPropValue: RawUtf8; aPropValueCaseSensitive: boolean;
  out Dest: PDocVariantData): boolean;
var
  ndx: PtrInt;
begin
  result := false;
  if not IsArray then
    exit;
  ndx := SearchItemByProp(aPropName, aPropValue, aPropValueCaseSensitive);
  if ndx >= 0 then
    result := _Safe(VValue[ndx], Dest);
end;

function TDocVariantData.GetJsonByStartName(const aStartName: RawUtf8): RawUtf8;
var
  Up: array[byte] of AnsiChar;
  temp: TTextWriterStackBuffer;
  n: integer;
  nam: PPUtf8Char;
  val: PVariant;
  W: TJsonWriter;
begin
  if (not IsObject) or
     (VCount = 0) then
  begin
    result := NULL_STR_VAR;
    exit;
  end;
  UpperCopy255(Up, aStartName)^ := #0;
  W := TJsonWriter.CreateOwnedStream(temp);
  try
    W.Add('{');
    n := VCount;
    nam := pointer(VName);
    val := pointer(VValue);
    repeat
      if IdemPChar(nam^, Up) then
      begin
        if (dvoSerializeAsExtendedJson in VOptions) and
           JsonPropNameValid(nam^) then
          W.AddNoJsonEscape(nam^, PStrLen(nam^ - _STRLEN)^)
        else
        begin
          W.Add('"');
          W.AddJsonEscape(nam^);
          W.Add('"');
        end;
        W.Add(':');
        W.AddVariant(val^, twJsonEscape);
        W.AddComma;
      end;
      dec(n);
      if n = 0 then
        break;
      inc(nam);
      inc(val);
    until false;
    W.CancelLastComma;
    W.Add('}');
    W.SetText(result);
  finally
    W.Free;
  end;
end;

function TDocVariantData.GetValuesByStartName(const aStartName: RawUtf8;
  TrimLeftStartName: boolean): variant;
var
  Up: array[byte] of AnsiChar;
  ndx: PtrInt;
  name: RawUtf8;
begin
  if aStartName = '' then
  begin
    result := Variant(self);
    exit;
  end;
  if (not IsObject) or
     (VCount = 0) then
  begin
    SetVariantNull(result{%H-});
    exit;
  end;
  TDocVariant.NewFast(result);
  UpperCopy255(Up{%H-}, aStartName)^ := #0;
  for ndx := 0 to VCount - 1 do
    if IdemPChar(Pointer(VName[ndx]), Up) then
    begin
      name := VName[ndx];
      if TrimLeftStartName then
        system.delete(name, 1, length(aStartName));
      TDocVariantData(result).AddValue(name, VValue[ndx]);
    end;
end;

procedure TDocVariantData.SetValueOrRaiseException(Index: integer;
  const NewValue: variant);
begin
  if cardinal(Index) >= cardinal(VCount) then
    raise EDocVariant.CreateUtf8(
      'Out of range Values[%] (count=%)', [Index, VCount])
  else
    VValue[Index] := NewValue;
end;

function TDocVariantData.SetValueByPath(const aPath: RawUtf8;
  const aValue: variant; aCreateIfNotExisting: boolean; aPathDelim: AnsiChar): boolean;
var
  csv: PUtf8Char;
  v: PDocVariantData;
  ndx: PtrInt;
  n: ShortString;
begin
  result := false;
  if IsArray then
    exit;
  csv := pointer(aPath);
  v := @self;
  repeat
    ndx := v^.InternalNextPath(csv, @n, aPathDelim);
    if csv = nil then
      break; // we reached the last item of the path, which is the value to set
    if ndx < 0 then
      if aCreateIfNotExisting then
      begin
        ndx := v^.InternalAdd(@n[1], ord(n[0])); // in two steps for FPC
        v := @v^.VValue[ndx];
        v^.InitClone(self); // same as root
      end
      else
        exit
    else if not _SafeObject(v^.VValue[ndx], v) then
      exit; // incorrect path
  until false;
  if ndx < 0 then
    ndx := v^.InternalAdd(@n[1], ord(n[0]));
  v^.InternalSetValue(ndx, aValue);
  result := true;
end;

procedure TDocVariantData.RetrieveNameOrRaiseException(
  Index: integer; var Dest: RawUtf8);
begin
  if (cardinal(Index) >= cardinal(VCount)) or
     (VName = nil) then
    if dvoReturnNullForUnknownProperty in VOptions then
      Dest := ''
    else
      raise EDocVariant.CreateUtf8(
        'Out of range Names[%] (count=%)', [Index, VCount])
  else
    Dest := VName[Index];
end;

procedure TDocVariantData.RetrieveValueOrRaiseException(Index: integer;
  var Dest: variant; DestByRef: boolean);
var
  Source: PVariant;
begin
  if cardinal(Index) >= cardinal(VCount) then
    InternalNotFound(Dest, Index)
  else if DestByRef then
    SetVariantByRef(VValue[Index], Dest)
  else
  begin
    Source := @VValue[Index];
    while PVarData(Source)^.VType = varVariantByRef do
      Source := PVarData(Source)^.VPointer;
    Dest := Source^;
  end;
end;

function TDocVariantData.RetrieveValueOrRaiseException(
  aName: PUtf8Char; aNameLen: integer; aCaseSensitive: boolean;
  var Dest: variant; DestByRef: boolean): boolean;
var
  ndx: integer;
begin
  ndx := GetValueIndex(aName, aNameLen, aCaseSensitive);
  if ndx < 0 then
    InternalNotFound(Dest, aName)
  else
    RetrieveValueOrRaiseException(ndx, Dest, DestByRef);
  result := ndx >= 0;
end;

function TDocVariantData.GetValueOrItem(const aNameOrIndex: variant): variant;
var
  wasString: boolean;
  Name: RawUtf8;
begin
  if IsArray then
    // fast index lookup e.g. for Value[1]
    RetrieveValueOrRaiseException(
      VariantToIntegerDef(aNameOrIndex, -1), result, true)
  else
  begin
    // by name lookup e.g. for Value['abc']
    VariantToUtf8(aNameOrIndex, Name, wasString);
    if wasString then
      RetrieveValueOrRaiseException(
        pointer(Name), length(Name), IsCaseSensitive, result, true)
    else
      RetrieveValueOrRaiseException(
        GetIntegerDef(pointer(Name), -1), result, true);
  end;
end;

procedure TDocVariantData.SetValueOrItem(const aNameOrIndex, aValue: variant);
var
  wasString: boolean;
  ndx: integer;
  Name: RawUtf8;
begin
  if IsArray then
    // fast index lookup e.g. for Value[1]
    SetValueOrRaiseException(VariantToIntegerDef(aNameOrIndex, -1), aValue)
  else
  begin
    // by name lookup e.g. for Value['abc']
    VariantToUtf8(aNameOrIndex, Name, wasString);
    if wasString then
    begin
      ndx := GetValueIndex(Name);
      if ndx < 0 then
        ndx := InternalAdd(Name);
      InternalSetValue(ndx, aValue);
    end
    else
      SetValueOrRaiseException(
        VariantToIntegerDef(aNameOrIndex, -1), aValue);
  end;
end;

function TDocVariantData.AddOrUpdateValue(const aName: RawUtf8;
  const aValue: variant; wasAdded: PBoolean; OnlyAddMissing: boolean): integer;
begin
  if IsArray then
    raise EDocVariant.CreateUtf8(
      'AddOrUpdateValue("%") on an array', [aName]);
  result := GetValueIndex(aName);
  if result < 0 then
  begin
    result := InternalAdd(aName);
    if wasAdded <> nil then
      wasAdded^ := true;
  end
  else
  begin
    if wasAdded <> nil then
      wasAdded^ := false;
    if OnlyAddMissing then
      exit;
  end;
  InternalSetValue(result, aValue);
end;

function TDocVariantData.ToJson: RawUtf8;
begin // note: FPC has troubles inlining this, but it is a slow method anyway
  DocVariantType.ToJson(@self, result, '', '', jsonCompact);
end;

function TDocVariantData.ToJson(const Prefix, Suffix: RawUtf8;
  Format: TTextWriterJsonFormat): RawUtf8;
begin
  DocVariantType.ToJson(@self, result, Prefix, Suffix, Format);
end;

procedure TDocVariantData.SaveToJsonFile(const FileName: TFileName);
var
  F: TStream;
  W: TJsonWriter;
begin
  if cardinal(VType) <> DocVariantVType then
    exit;
  F := TFileStreamEx.Create(FileName, fmCreate);
  try
    W := TJsonWriter.Create(F, 65536);
    try
      DocVariantType.ToJson(W, @self);
      W.FlushFinal;
    finally
      W.Free;
    end;
  finally
    F.Free;
  end;
end;

function TDocVariantData.ToNonExpandedJson: RawUtf8;
var
  field: TRawUtf8DynArray;
  fieldCount, r, f: PtrInt;
  W: TJsonWriter;
  row: PDocVariantData;
  temp: TTextWriterStackBuffer;
begin
  if not IsArray then
  begin
    result := '';
    exit;
  end;
  if VCount = 0 then
  begin
    result := '[]';
    exit;
  end;
  fieldCount := 0;
  with _Safe(VValue[0])^ do
    if IsObject then
    begin
      field := VName;
      fieldCount := VCount;
    end;
  if fieldCount = 0 then
    raise EDocVariant.Create('ToNonExpandedJson: Value[0] is not an object');
  W := TJsonWriter.CreateOwnedStream(temp);
  try
    W.Add('{"fieldCount":%,"rowCount":%,"values":[', [fieldCount, VCount]);
    for f := 0 to fieldCount - 1 do
    begin
      W.Add('"');
      W.AddJsonEscape(pointer(field[f]));
      W.Add('"', ',');
    end;
    for r := 0 to VCount - 1 do
    begin
      row := _Safe(VValue[r]);
      if (r > 0) and
         ((not row^.IsObject) or
          (row^.VCount <> fieldCount)) then
        raise EDocVariant.CreateUtf8(
          'ToNonExpandedJson: Value[%] not expected object', [r]);
      for f := 0 to fieldCount - 1 do
        if (r > 0) and
           not PropNameEquals(row^.VName[f], field[f]) then
          raise EDocVariant.CreateUtf8(
            'ToNonExpandedJson: Value[%] field=% expected=%',
            [r, row^.VName[f], field[f]])
        else
        begin
          W.AddVariant(row^.VValue[f], twJsonEscape);
          W.AddComma;
        end;
    end;
    W.CancelLastComma;
    W.Add(']', '}');
    W.SetText(result);
  finally
    W.Free;
  end;
end;

procedure TDocVariantData.ToRawUtf8DynArray(out Result: TRawUtf8DynArray);
var
  ndx: PtrInt;
  wasString: boolean;
begin
  if IsObject then
    raise EDocVariant.Create('ToRawUtf8DynArray expects a dvArray');
  if IsArray then
  begin
    SetLength(Result, VCount);
    for ndx := 0 to VCount - 1 do
      VariantToUtf8(VValue[ndx], Result[ndx], wasString);
  end;
end;

function TDocVariantData.ToRawUtf8DynArray: TRawUtf8DynArray;
begin
  ToRawUtf8DynArray(result);
end;

function TDocVariantData.ToCsv(const Separator: RawUtf8): RawUtf8;
var
  tmp: TRawUtf8DynArray; // fast enough in practice
begin
  ToRawUtf8DynArray(tmp);
  result := RawUtf8ArrayToCsv(tmp, Separator);
end;

procedure TDocVariantData.ToTextPairsVar(out Result: RawUtf8;
  const NameValueSep, ItemSep: RawUtf8; escape: TTextWriterKind);
var
  ndx: PtrInt;
  temp: TTextWriterStackBuffer;
begin
  if IsArray then
    raise EDocVariant.Create('ToTextPairs expects a dvObject');
  if (VCount > 0) and
     IsObject then
    with TJsonWriter.CreateOwnedStream(temp) do
      try
        ndx := 0;
        repeat
          AddString(VName[ndx]);
          AddString(NameValueSep);
          AddVariant(VValue[ndx], escape);
          inc(ndx);
          if ndx = VCount then
            break;
          AddString(ItemSep);
        until false;
        SetText(Result);
      finally
        Free;
      end;
end;

function TDocVariantData.ToTextPairs(const NameValueSep: RawUtf8;
  const ItemSep: RawUtf8; Escape: TTextWriterKind): RawUtf8;
begin
  ToTextPairsVar(result, NameValueSep, ItemSep, Escape);
end;

procedure TDocVariantData.ToArrayOfConst(out Result: TTVarRecDynArray);
begin
  if IsObject then
    raise EDocVariant.Create('ToArrayOfConst expects a dvArray');
  if IsArray then
    VariantsToArrayOfConst(VValue, VCount, Result);
end;

function TDocVariantData.ToArrayOfConst: TTVarRecDynArray;
begin
  ToArrayOfConst(result);
end;

function TDocVariantData.ToUrlEncode(const UriRoot: RawUtf8): RawUtf8;
var
  json: RawUtf8; // temporary in-place modified buffer
begin
  DocVariantType.ToJson(@self, json);
  result := UrlEncodeJsonObject(UriRoot, Pointer(json), []);
end;

function TDocVariantData.GetOrAddIndexByName(const aName: RawUtf8): integer;
begin
  result := GetValueIndex(aName);
  if result < 0 then
    result := InternalAdd(aName);
end;

function TDocVariantData.GetOrAddPVariantByName(const aName: RawUtf8): PVariant;
var
  ndx: PtrInt;
begin
  ndx := GetOrAddIndexByName(aName); // in two steps for FPC
  result := @VValue[ndx];
end;

function TDocVariantData.GetPVariantByName(const aName: RawUtf8): PVariant;
var
  ndx: PtrInt;
begin
  ndx := GetValueIndex(aName);
  if ndx < 0 then
    result := InternalNotFound(pointer(aName))
  else
    result := @VValue[ndx];
end;

function TDocVariantData.GetInt64ByName(const aName: RawUtf8): Int64;
begin
  if not VariantToInt64(GetPVariantByName(aName)^, result) then
    result := 0;
end;

function TDocVariantData.GetRawUtf8ByName(const aName: RawUtf8): RawUtf8;
var
  wasString: boolean;
  v: PVariant;
begin
  v := GetPVariantByName(aName);
  if PVarData(v)^.VType <= varNull then // default VariantToUtf8(null)='null'
    result := ''
  else
    VariantToUtf8(v^, result, wasString);
end;

function TDocVariantData.GetStringByName(const aName: RawUtf8): string;
begin
  result := VariantToString(GetPVariantByName(aName)^);
end;

procedure TDocVariantData.SetInt64ByName(const aName: RawUtf8;
  const aValue: Int64);
begin
  GetOrAddPVariantByName(aName)^ := aValue;
end;

procedure TDocVariantData.SetRawUtf8ByName(const aName, aValue: RawUtf8);
begin
  RawUtf8ToVariant(aValue, GetOrAddPVariantByName(aName)^);
end;

procedure TDocVariantData.SetStringByName(const aName: RawUtf8;
  const aValue: string);
begin
  RawUtf8ToVariant(StringToUtf8(aValue), GetOrAddPVariantByName(aName)^);
end;

function TDocVariantData.GetBooleanByName(const aName: RawUtf8): boolean;
begin
  if not VariantToBoolean(GetPVariantByName(aName)^, result) then
    result := false;
end;

procedure TDocVariantData.SetBooleanByName(const aName: RawUtf8;
  aValue: boolean);
begin
  GetOrAddPVariantByName(aName)^ := aValue;
end;

function TDocVariantData.GetDoubleByName(const aName: RawUtf8): Double;
begin
  if not VariantToDouble(GetPVariantByName(aName)^, result) then
    result := 0;
end;

procedure TDocVariantData.SetDoubleByName(const aName: RawUtf8;
  const aValue: Double);
begin
  GetOrAddPVariantByName(aName)^ := aValue;
end;

function TDocVariantData.GetDocVariantExistingByName(const aName: RawUtf8;
  aNotMatchingKind: TDocVariantKind): PDocVariantData;
begin
  result := GetAsDocVariantSafe(aName);
  if result^.GetKind = aNotMatchingKind then
    result := @DocVariantDataFake;
end;

function TDocVariantData.GetDocVariantOrAddByName(const aName: RawUtf8;
  aKind: TDocVariantKind): PDocVariantData;
var
  ndx: PtrInt;
begin
  ndx := GetOrAddIndexByName(aName);
  result := _Safe(VValue[ndx]);
  if result^.Kind <> aKind then
  begin
    result := @VValue[ndx];
    VarClear(PVariant(result)^);
    result^.Init(VOptions, aKind);
  end;
end;

function TDocVariantData.GetObjectExistingByName(
  const aName: RawUtf8): PDocVariantData;
begin
  result := GetDocVariantExistingByName(aName, dvArray);
end;

function TDocVariantData.GetObjectOrAddByName(
  const aName: RawUtf8): PDocVariantData;
begin
  result := GetDocVariantOrAddByName(aName, dvObject);
end;

function TDocVariantData.GetArrayExistingByName(
  const aName: RawUtf8): PDocVariantData;
begin
  result := GetDocVariantExistingByName(aName, dvObject);
end;

function TDocVariantData.GetArrayOrAddByName(
  const aName: RawUtf8): PDocVariantData;
begin
  result := GetDocVariantOrAddByName(aName, dvArray);
end;

function TDocVariantData.GetAsDocVariantByIndex(
  aIndex: integer): PDocVariantData;
begin
  if cardinal(aIndex) < cardinal(VCount) then
    result := _Safe(VValue[aIndex])
  else
    result := InternalNotFound(aIndex);
end;

function _Obj(const NameValuePairs: array of const;
  Options: TDocVariantOptions): variant;
begin
  VarClear(result{%H-});
  TDocVariantData(result).InitObject(NameValuePairs, Options);
end;

function _Arr(const Items: array of const;
  Options: TDocVariantOptions): variant;
begin
  VarClear(result{%H-});
  TDocVariantData(result).InitArray(Items, Options);
end;

procedure _ObjAddProp(const Name: RawUtf8; const Value: variant;
  var Obj: variant);
var
  o: PDocVariantData;
begin
  if _SafeObject(Obj, o) then
  begin
    // append new names/values to existing object
    if o <> @Obj then
      // ensure not stored by reference
      TVarData(Obj) := PVarData(o)^;
    o^.AddOrUpdateValue(Name, Value);
  end
  else
  begin
    // create new object
    VarClear(Obj);
    TDocVariantData(Obj).InitObject([Name, Value], JSON_FAST);
  end
end;

procedure _ObjAddProp(const Name: RawUtf8; const Value: TDocVariantData;
  var Obj: variant);
begin
  _ObjAddProp(Name, variant(Value), Obj);
end;

procedure _ObjAddPropU(const Name: RawUtf8; const Value: RawUtf8;
  var Obj: variant);
var
  v: variant;
begin
  RawUtf8ToVariant(Value, v);
  _ObjAddProp(Name, v, Obj);
end;

procedure _ObjAddProps(const NameValuePairs: array of const;
  var Obj: variant);
var
  o: PDocVariantData;
begin
  if _SafeObject(Obj, o) then
  begin
    // append new names/values to existing object
    if o <> @Obj then
      // ensure not stored by reference
      TVarData(Obj) := PVarData(o)^;
    o^.AddNameValuesToObject(NameValuePairs);
  end
  else
  begin
    // create new object
    VarClear(Obj);
    TDocVariantData(Obj).InitObject(NameValuePairs, JSON_FAST);
  end
end;

procedure _ObjAddProps(const Document: variant; var Obj: variant);
var
  ndx: PtrInt;
  d, o: PDocVariantData;
begin
  o := _Safe(Obj);
  if _SafeObject(Document, d) then
    if not o.IsObject then
      Obj := Document
    else
      for ndx := 0 to d^.VCount - 1 do
        o^.AddOrUpdateValue(d^.VName[ndx], d^.VValue[ndx]);
end;

function _ObjFast(const NameValuePairs: array of const): variant;
begin
  VarClear(result{%H-});
  TDocVariantData(result).InitObject(NameValuePairs, JSON_FAST);
end;

function _ObjFast(aObject: TObject;
  aOptions: TTextWriterWriteObjectOptions): variant;
begin
  ObjectToVariant(aObject, result, aOptions);
end;

function _ArrFast(const Items: array of const): variant;
begin
  VarClear(result{%H-});
  TDocVariantData(result).InitArray(Items, JSON_FAST);
end;

function _Json(const Json: RawUtf8; Options: TDocVariantOptions): variant;
begin
  _Json(Json, result, Options);
end;

function _JsonFast(const Json: RawUtf8): variant;
begin
  _Json(Json, result, JSON_FAST);
end;

function _JsonFastFloat(const Json: RawUtf8): variant;
begin
  _Json(Json, result, JSON_FAST_FLOAT);
end;

function _JsonFastExt(const Json: RawUtf8): variant;
begin
  _Json(Json, result, JSON_FAST_EXTENDED);
end;

function _JsonFmt(const Format: RawUtf8; const Args, Params: array of const;
  Options: TDocVariantOptions): variant;
begin
  _JsonFmt(Format, Args, Params, Options, result);
end;

procedure _JsonFmt(const Format: RawUtf8; const Args, Params: array of const;
  Options: TDocVariantOptions; out Result: variant);
var
  temp: RawUtf8;
begin
  temp := FormatUtf8(Format, Args, Params, true);
  if TDocVariantData(Result).InitJsonInPlace(pointer(temp), Options) = nil then
    TDocVariantData(Result).ClearFast;
end;

function _JsonFastFmt(const Format: RawUtf8;
  const Args, Params: array of const): variant;
begin
  _JsonFmt(Format, Args, Params, JSON_FAST, result);
end;

function _Json(const Json: RawUtf8; var Value: variant;
  Options: TDocVariantOptions): boolean;
begin
  VarClear(Value);
  if not TDocVariantData(Value).InitJson(Json, Options) then
  begin
    TDocVariantData(Value).ClearFast;
    result := false;
  end
  else
    result := true;
end;

procedure _Unique(var DocVariant: variant);
begin
  // TDocVariantData(DocVariant): InitCopy() will check the DocVariant type
  TDocVariantData(DocVariant).InitCopy(DocVariant, JSON_[mDefault]);
end;

procedure _UniqueFast(var DocVariant: variant);
begin
  // TDocVariantData(DocVariant): InitCopy() will check the DocVariant type
  TDocVariantData(DocVariant).InitCopy(DocVariant, JSON_[mFast]);
end;

function _Copy(const DocVariant: variant): variant;
begin
  result := TDocVariant.NewUnique(DocVariant, JSON_[mDefault]);
end;

function _CopyFast(const DocVariant: variant): variant;
begin
  result := TDocVariant.NewUnique(DocVariant, JSON_[mFast]);
end;

function _ByRef(const DocVariant: variant; Options: TDocVariantOptions): variant;
begin
  VarClear(result{%H-});
  TDocVariantData(result) := _Safe(DocVariant)^; // fast byref copy
  TDocVariantData(result).SetOptions(Options);
end;

procedure _ByRef(const DocVariant: variant; out Dest: variant;
  Options: TDocVariantOptions);
begin
  TDocVariantData(Dest) := _Safe(DocVariant)^; // fast byref copy
  TDocVariantData(Dest).SetOptions(Options);
end;


{ ************** JSON Parsing into Variant }

function GetVariantFromNotStringJson(Json: PUtf8Char; var Value: TVarData;
  AllowDouble: boolean): boolean;
begin
  if Json <> nil then
    Json := GotoNextNotSpace(Json);
  if (Json = nil) or
     ((PInteger(Json)^ = NULL_LOW) and
      (jcEndOfJsonValueField in JSON_CHARS[Json[4]])) then
    TRttiVarData(Value).VType := varNull
  else if (PInteger(Json)^ = FALSE_LOW) and
          (Json[4] = 'e') and
          (jcEndOfJsonValueField in JSON_CHARS[Json[5]]) then
  begin
    TRttiVarData(Value).VType := varBoolean;
    Value.VInteger := ord(false);
  end
  else if (PInteger(Json)^ = TRUE_LOW) and
          (jcEndOfJsonValueField in JSON_CHARS[Json[4]]) then
  begin
    TRttiVarData(Value).VType := varBoolean;
    Value.VInteger := ord(true);
  end
  else
  begin
    Json := GetNumericVariantFromJson(Json, Value, AllowDouble);
    if (Json = nil) or
       (GotoNextNotSpace(Json)^ <> #0) then
    begin
      result := false;
      exit;
    end;
  end;
  result := true;
end;

function GotoEndOfJsonNumber(P: PUtf8Char; var PEndNum: PUtf8Char): PUtf8Char;
  {$ifdef HASINLINE} inline; {$endif} // inlined for better code generation
var
  tab: PJsonCharSet;
begin
  result := P;
  tab := @JSON_CHARS;
  repeat
    inc(result);
  until not (jcDigitFloatChar in tab[result^]);
  PEndNum := result;
  while not (jcEndOfJsonFieldNotName in tab[result^]) do
    inc(result); // #0, ',', ']', '}'
end;

{$ifndef PUREMORMOT2}
procedure GetJsonToAnyVariant(var Value: variant; var Json: PUtf8Char;
  EndOfObject: PUtf8Char; Options: PDocVariantOptions; AllowDouble: boolean);
var
  info: TGetJsonField;
begin
  info.Json := Json;
  JsonToAnyVariant(Value, Info, Options, AllowDouble);
  if EndOfObject <> nil then
    EndOfObject^ := info.EndOfObject;
  Json := info.Json;
end;
{$endif PUREMORMOT2}

procedure JsonToAnyVariant(var Value: variant; var Info: TGetJsonField;
  Options: PDocVariantOptions; AllowDouble: boolean);
var
  V: TVarData absolute Value;
  n: integer;
  t: ^TSynInvokeableVariantType;
  J, J2: PUtf8Char;
  EndOfObject2: AnsiChar;
  wasParsedWithinString: boolean;
label
  parse, parsed, astext, endobj;
begin
  if PInteger(@V)^ <> 0 then
    VarClearProc(V);
  if Info.Json = nil then
    exit;
  Info.EndOfObject := ' ';
  if (Options <> nil) and
     (dvoAllowDoubleValue in Options^) then
    AllowDouble := true;
  wasParsedWithinString := false;
  J := Info.Json;
  while (J^ <= ' ') and
        (J^ <> #0) do
    inc(J);
  case JSON_TOKENS[J^] of
    jtFirstDigit:  // '-', '0'..'9': numbers are directly processed
      begin
        Info.Value := J;
        J := GetNumericVariantFromJson(J, V, AllowDouble);
        if J = nil then
        begin
          // not a supported number
          if AllowDouble then
          begin
            Info.Json := nil; // we expected the precision to be enough
            exit;
          end;
          // it may be a double value, but we didn't allow them -> store as text
          J := Info.Value;
          repeat
            inc(J); // #0, ',', ']', '}'
          until not (jcDigitFloatChar in JSON_CHARS[J^]);
          Info.ValueLen := J - Info.Value;
          J := GotoNextNotSpace(J);
          Info.EndOfObject := J^;
          if J^ <> #0 then
            inc(J);
          Info.Json := J;
          goto astext;
        end;
        // we parsed a full number as variant
endobj: Info.ValueLen := J - Info.Value;
        while (J^ <= ' ') and
              (J^ <> #0) do
          inc(J);
        Info.EndOfObject := J^;
        if J^ <> #0 then
          inc(J);
        Info.Json := J;
        exit;
      end;
    jtDoubleQuote:
      begin
        Info.Json := J;
        if (Options <> nil) and
           (dvoJsonObjectParseWithinString in Options^) then
        begin
          Info.GetJsonField;
          J := Info.Value;
          wasParsedWithinString := true;
        end
        else
        begin
          // parse string/numerical values (or true/false/null constants)
parse:    Info.GetJsonField;
parsed:   if Info.WasString or
             not GetVariantFromNotStringJson(Info.Value, V, AllowDouble) then
          begin
astext:     TRttiVarData(V).VType := varString;
            V.VAny := nil; // avoid GPF below
            FastSetString(RawUtf8(V.VAny), Info.Value, Info.Valuelen);
          end;
          exit;
        end;
      end;
    jtNullFirstChar:
      if (PInteger(J)^ = NULL_LOW) and
         (jcEndOfJsonValueField in JSON_CHARS[J[4]]) then
      begin
        Info.Value := J;
        TRttiVarData(V).VType := varNull;
        inc(J, 4);
        goto endobj;
      end;
    jtFalseFirstChar:
      if (PInteger(J + 1)^ = FALSE_LOW2) and
         (jcEndOfJsonValueField in JSON_CHARS[J[5]]) then
      begin
        Info.Value := J;
        TRttiVarData(V).VType := varBoolean;
        V.VInteger := ord(false);
        inc(J, 5);
        goto endobj;
      end;
    jtTrueFirstChar:
      if (PInteger(J)^ = TRUE_LOW) and
         (jcEndOfJsonValueField in JSON_CHARS[J[4]]) then
      begin
        Info.Value := J;
        TRttiVarData(V).VType := varBoolean;
        V.VInteger := ord(true);
        inc(J, 4);
        goto endobj;
      end;
  end;
  // if we reach here, input Json may be some complex value
  if Options = nil then
  begin
    Info.Json := nil;
    exit; // clearly invalid basic JSON
  end;
  if not (dvoJsonParseDoNotTryCustomVariants in Options^) then
  begin
    // first call TryJsonToVariant() overriden method for any complex content
    t := pointer(SynVariantTryJsonTypes);
    if t <> nil then
    begin
      n := PDALen(PAnsiChar(t) - _DALEN)^ + _DAOFF; // call all TryJsonToVariant()
      repeat
        J2 := J;
        // currently, only implemented by mormot.db.nosql.bson BsonVariantType
        if t^.TryJsonToVariant(J2, Value, @EndOfObject2) then
        begin
          if not wasParsedWithinString then
          begin
            Info.EndOfObject := EndOfObject2;
            Info.Json := J2;
          end;
          exit;
        end;
        dec(n);
        if n = 0 then
          break;
        inc(t);
      until false;
    end;
  end;
  if J^ in ['{', '['] then
  begin
    // default Json parsing and conversion to TDocVariant instance
    J := TDocVariantData(Value).InitJsonInPlace(J, Options^, @EndOfObject2);
    if J = nil then
    begin
      TDocVariantData(Value).ClearFast;
      Info.Json := nil;
      exit; // error parsing
    end;
    if not wasParsedWithinString then
    begin
      Info.EndOfObject := EndOfObject2;
      Info.Json := J;
    end;
  end
  else // back to simple variant types
    if wasParsedWithinString then
      goto parsed
    else
    begin
      Info.Json := J;
      goto parse;
    end;
end;

function TextToVariantNumberTypeNoDouble(Json: PUtf8Char): cardinal;
var
  start: PUtf8Char;
  c: AnsiChar;
begin
  result := varString;
  c := Json[0];
  if (jcDigitFirstChar in JSON_CHARS[c]) and // ['-', '0'..'9']
     (((c >= '1') and
       (c <= '9')) or      // is first char numeric?
     ((c = '0') and
      ((Json[1] = '.') or
       (Json[1] = #0))) or // '012' is not Json, but '0.xx' and '0' are
     ((c = '-') and
      (Json[1] >= '0') and
      (Json[1] <= '9'))) then  // negative number
  begin
    start := Json;
    repeat
      inc(Json)
    until (Json^ < '0') or
          (Json^ > '9'); // check digits
    case Json^ of
      #0:
        if Json - start <= 19 then
          // no decimal, and matcthing signed Int64 precision
          result := varInt64;
      '.':
        if (Json[1] >= '0') and
           (Json[1] <= '9') and
           (Json[2] in [#0, '0'..'9']) then
          if (Json[2] = #0) or
             (Json[3] = #0) or
             ((Json[3] >= '0') and
              (Json[3] <= '9') and
              (Json[4] = #0) or
             ((Json[4] >= '0') and
              (Json[4] <= '9') and
              (Json[5] = #0))) then
            result := varCurrency; // currency ###.1234 number
    end;
  end;
end;

function TextToVariantNumberType(Json: PUtf8Char): cardinal;
var
  start: PUtf8Char;
  exp: PtrInt;
  c: AnsiChar;
label
  exponent;
begin
  result := varString;
  c := Json[0];
  if (jcDigitFirstChar in JSON_CHARS[c]) and // ['-', '0'..'9']
     (((c >= '1') and
       (c <= '9')) or      // is first char numeric?
     ((c = '0') and
      ((Json[1] = '.') or
       (Json[1] = #0))) or // '012' is not Json, but '0.xx' and '0' are
     ((c = '-') and
      (Json[1] >= '0') and
      (Json[1] <= '9'))) then  // negative number
  begin
    start := Json;
    repeat
      inc(Json)
    until (Json^ < '0') or
          (Json^ > '9'); // check digits
    case Json^ of
      #0:
        if Json - start <= 19 then // signed Int64 precision
          result := varInt64
        else
          result := varDouble; // we may loose precision, but still a number
      '.':
        if (Json[1] >= '0') and
           (Json[1] <= '9') and
           (Json[2] in [#0, '0'..'9']) then
          if (Json[2] = #0) or
             (Json[3] = #0) or
             ((Json[3] >= '0') and
              (Json[3] <= '9') and
              (Json[4] = #0) or
             ((Json[4] >= '0') and
              (Json[4] <= '9') and
              (Json[5] = #0))) then
            result := varCurrency // currency ###.1234 number
          else
          begin
            repeat // more than 4 decimals
              inc(Json)
            until (Json^ < '0') or
                  (Json^ > '9');
            case Json^ of
              #0:
                result := varDouble;
              'e',
              'E':
                begin
exponent:         inc(Json); // inlined custom GetInteger()
                  start := Json;
                  c := Json^;
                  if (c = '-') or
                     (c = '+') then
                  begin
                    inc(Json);
                    c := Json^;
                  end;
                  inc(Json);
                  dec(c, 48);
                  if c > #9 then
                    exit;
                  exp := ord(c);
                  c := Json^;
                  dec(c, 48);
                  if c <= #9 then
                  begin
                    inc(Json);
                    exp := exp * 10 + ord(c);
                    c := Json^;
                    dec(c, 48);
                    if c <= #9 then
                    begin
                      inc(Json);
                      exp := exp * 10 + ord(c);
                    end;
                  end;
                  if Json^ <> #0 then
                    exit;
                  if start^ = '-' then
                    exp := -exp;
                  if (exp > -324) and
                     (exp < 308) then
                    result := varDouble; // 5.0 x 10^-324 .. 1.7 x 10^308
                end;
            end;
          end;
      'e',
      'E':
        goto exponent;
    end;
  end;
end;

const
  CURRENCY_FACTOR: array[-4 .. -1] of integer = (1, 10, 100, 1000);

function GetNumericVariantFromJson(Json: PUtf8Char; var Value: TVarData;
  AllowVarDouble: boolean): PUtf8Char;
var
  // logic below is extracted from mormot.core.base.pas' GetExtended()
  remdigit: integer;
  frac, exp: PtrInt;
  c: AnsiChar;
  flags: set of (fNeg, fNegExp, fValid);
  v64: Int64; // allows 64-bit resolution for the digits (match 80-bit extended)
  d: double;
begin
  // 1. parse input text as number into v64, frac, digit, exp
  result := nil; // return nil to indicate parsing error
  byte(flags) := 0;
  v64 := 0;
  frac := 0;
  if Json = nil then
    exit;
  c := Json^;
  if c = '-' then // note: '+xxx' is not valid Json so is not handled here
  begin
    c := Json[1];
    inc(Json);
    include(flags, fNeg);
  end;
  if (c = '0') and
     (Json[1] >= '0') and
     (Json[1] <= '9') then // '012' is not Json, but '0.xx' and '0' are
    exit;
  remdigit := 19;    // max Int64 resolution
  repeat
    if (c >= '0') and
       (c <= '9') then
    begin
      inc(Json);
      dec(remdigit); // over-required digits are just ignored
      if remdigit >= 0 then
      begin
        dec(c, ord('0'));
        {$ifdef CPU64}
        v64 := v64 * 10;
        {$else}
        v64 := v64 shl 3 + v64 + v64;
        {$endif CPU64}
        inc(v64, byte(c));
        c := Json^;
        include(flags, fValid);
        if frac <> 0 then
          dec(frac); // frac<0 for digits after '.'
        continue;
      end;
      c := Json^;
      if frac >= 0 then
        inc(frac);   // frac>0 to handle #############00000
      continue;
    end;
    if c <> '.' then
      break;
    c := Json[1];
    if (frac > 0) or
       (c = #0) then // avoid ##.
      exit;
    inc(json);
    dec(frac);
  until false;
  if frac < 0 then
    inc(frac);       // adjust digits after '.'
  if (c = 'E') or
     (c = 'e') then
  begin
    c := Json[1];
    inc(Json);
    exp := 0;
    exclude(flags, fValid);
    if c = '+' then
      inc(Json)
    else if c = '-' then
    begin
      inc(Json);
      include(flags, fNegExp);
    end;
    repeat
      c := Json^;
      if (c < '0') or
         (c > '9') then
        break;
      inc(Json);
      dec(c, ord('0'));
      exp := (exp * 10) + byte(c);
      include(flags, fValid);
    until false;
    if fNegExp in flags then
      dec(frac, exp)
    else
      inc(frac, exp);
  end;
  if not (fValid in flags) then
    exit;
  if fNeg in flags then
    v64 := -v64;
  // 2. now v64, frac, digit, exp contain number parsed from Json
  if (frac = 0) and
     (remdigit >= 0) then
  begin
    // return an integer or Int64 value
    Value.VInt64 := v64;
    if remdigit <= 9 then
      TRttiVarData(Value).VType := varInt64
    else
      TRttiVarData(Value).VType := varInteger;
  end
  else if (frac < 0) and
          (frac >= -4) then
  begin
    // currency as ###.0123
    TRttiVarData(Value).VType := varCurrency;
    Value.VInt64 := v64 * CURRENCY_FACTOR[frac]; // as round(CurrValue*10000)
  end
  else if AllowVarDouble and
          (frac > -324) then // 5.0 x 10^-324 .. 1.7 x 10^308
  begin
    // converted into a double value
    exp := PtrUInt(@POW10);
    if frac >= -31 then
      if frac <= 31 then
        d := PPow10(exp)[frac]                 // -31 .. + 31
      else if (18 - remdigit) + integer(frac) >= 308 then
        exit                                   // +308 ..
      else
        d := HugePower10Pos(frac, PPow10(exp)) // +32 .. +307
    else
      d := HugePower10Neg(frac, PPow10(exp));  // .. -32
    Value.VDouble := d * v64;
    TRttiVarData(Value).VType := varDouble;
  end
  else
    exit;
  result := Json; // returns the first char after the parsed number
end;

procedure UniqueVariant(Interning: TRawUtf8Interning; var aResult: variant;
  aText: PUtf8Char; aTextLen: PtrInt; aAllowVarDouble: boolean);
var
  tmp: RawUtf8;
begin
  if not GetVariantFromNotStringJson(
           aText, TVarData(aResult), aAllowVarDouble) then
  begin
    FastSetString(tmp, aText, aTextLen);
    if Interning = nil then
      RawUtf8ToVariant(tmp, aResult)
    else
      Interning.UniqueVariant(aResult, tmp);
  end;
end;

procedure TextToVariant(const aValue: RawUtf8; AllowVarDouble: boolean;
  out aDest: variant);
begin
  try
    if GetVariantFromNotStringJson(pointer(aValue), TVarData(aDest), AllowVarDouble) then
      exit;
  except // some obscure floating point exception may occur
  end;
  RawUtf8ToVariant(aValue, aDest);
end;

function GetNextItemToVariant(var P: PUtf8Char; out Value: Variant;
  Sep: AnsiChar; AllowDouble: boolean): boolean;
var
  temp: RawUtf8;
begin
  if P = nil then
    result := false
  else
  begin
    GetNextItem(P, Sep, temp);
    TextToVariant(temp, AllowDouble, Value);
    result := true;
  end;
end;

procedure GetVariantFromJsonField(Json: PUtf8Char; wasString: boolean;
  var Value: variant; TryCustomVariants: PDocVariantOptions;
  AllowDouble: boolean; JsonLen: integer);
var
  V: TVarData absolute Value;
  info: TGetJsonField;
begin
  // first handle any strict-Json syntax objects or arrays into custom variants
  if (TryCustomVariants <> nil) and
     (Json <> nil) then
    if (GotoNextNotSpace(Json)^ in ['{', '[']) and
       not wasString then
    begin // also supports dvoJsonObjectParseWithinString
      info.Json := Json;
      JsonToAnyVariant(Value, info, TryCustomVariants, AllowDouble);
      exit;
    end
    else if dvoAllowDoubleValue in TryCustomVariants^ then
      AllowDouble := true;
  // handle simple text or numerical values
  VarClear(Value);
  // try any numerical or true/false/null value
  if wasString or
     not GetVariantFromNotStringJson(Json, V, AllowDouble) then
  begin
    // found no numerical value -> return a string in the expected format
    TRttiVarData(Value).VType := varString;
    V.VString := nil; // avoid GPF below
    if JsonLen = 0 then
      JsonLen := StrLen(Json);
    FastSetString(RawUtf8(V.VString), Json, JsonLen);
  end;
end;

procedure _BinaryVariantLoadAsJson(var Value: variant; Json: PUtf8Char;
  TryCustomVariant: pointer);
var
  info: TGetJsonField;
begin
  if TryCustomVariant = nil then
    TryCustomVariant := @JSON_[mFast];
  info.Json := Json;
  JsonToAnyVariant(Value, info, TryCustomVariant, {double=}true);
end;

function VariantLoadJson(var Value: Variant; const Json: RawUtf8;
  TryCustomVariants: PDocVariantOptions; AllowDouble: boolean): boolean;
var
  tmp: TSynTempBuffer;
  info: TGetJsonField;
begin
  tmp.Init(Json); // temp copy before in-place decoding
  try
    info.Json := tmp.buf;
    JsonToAnyVariant(Value, info, TryCustomVariants, AllowDouble);
    result := info.Json <> nil;
  finally
    tmp.Done;
  end;
end;

function VariantLoadJson(const Json: RawUtf8;
  TryCustomVariants: PDocVariantOptions; AllowDouble: boolean): variant;
begin
  VariantLoadJson(result, Json, TryCustomVariants, AllowDouble);
end;

function JsonToVariantInPlace(var Value: Variant; Json: PUtf8Char;
  Options: TDocVariantOptions; AllowDouble: boolean): PUtf8Char;
var
  info: TGetJsonField;
begin
  info.Json := Json;
  JsonToAnyVariant(Value, info, @Options, AllowDouble);
  result := info.Json;
end;

function JsonToVariant(const Json: RawUtf8; Options: TDocVariantOptions;
  AllowDouble: boolean): variant;
begin
  VariantLoadJson(result, Json, @Options, AllowDouble);
end;

procedure MultiPartToDocVariant(const MultiPart: TMultiPartDynArray;
  var Doc: TDocVariantData; Options: PDocVariantOptions);
var
  ndx: PtrInt;
  v: variant;
begin
  if Options = nil then
    Doc.InitFast(dvObject)
  else
    Doc.Init(Options^, dvObject);
  for ndx := 0 to high(multipart) do
    with MultiPart[ndx] do
      if ContentType = TEXT_CONTENT_TYPE then
      begin
        // append as regular "Name":"TextValue" field
        RawUtf8ToVariant(Content, v);
        Doc.AddValue(name, v);
      end
      else
        // append binary file as an object, with Base64-encoded data
        Doc.AddValue(name, _ObjFast([
          'data',        BinToBase64(Content),
          'filename',    FileName,
          'contenttype', ContentType]));
end;


{ ************** Variant Binary Serialization }

{$ifndef PUREMORMOT2}

function VariantSaveLength(const Value: variant): integer;
begin
  result := {%H-}BinarySaveLength(@Value, TypeInfo(Variant), nil, [rkVariant]);
end;

function VariantSave(const Value: variant; Dest: PAnsiChar): PAnsiChar;
var
  dummy: integer;
begin
  result := {%H-}BinarySave(@Value, Dest, TypeInfo(Variant), dummy, [rkVariant]);
end;

{$endif PUREMORMOT2}

function VariantSave(const Value: variant): RawByteString;
begin
  result := BinarySave(@Value, TypeInfo(Variant), [rkVariant]);
end;

function VariantLoad(var Value: variant; Source: PAnsiChar;
  CustomVariantOptions: PDocVariantOptions; SourceMax: PAnsiChar): PAnsiChar;
begin
  {$ifndef PUREMORMOT2}
  if SourceMax = nil then
    // mORMot 1 unsafe backward compatible: assume fake 100MB Source input
    SourceMax := Source + 100 shl 20;
  {$endif PUREMORMOT2}
  result := BinaryLoad(@Value, Source, TypeInfo(Variant), nil, SourceMax,
    [rkVariant], CustomVariantOptions);
end;

function VariantLoad(const Bin: RawByteString;
  CustomVariantOptions: PDocVariantOptions): variant;
begin
  BinaryLoad(@result, Bin, TypeInfo(Variant),
    [rkVariant], CustomVariantOptions);
end;

procedure FromVarVariant(var Source: PByte; var Value: variant;
  CustomVariantOptions: PDocVariantOptions; SourceMax: PByte);
begin
  Source := PByte(VariantLoad(Value, pointer(Source),
    CustomVariantOptions, pointer(SourceMax)));
end;

var
  // naive but efficient type cache - e.g. for TBsonVariant or TQuickJsVariant
  LastDispInvoke: TSynInvokeableVariantType;

// sysdispinvoke() replacement to meet TSynInvokeableVariantType expectations
procedure NewDispInvoke(Dest: PVarData;
{$ifdef FPC_VARIANTSETVAR}
  var Source: TVarData;
{$else} // see http://mantis.freepascal.org/view.php?id=26773
  const Source: TVarData; // "[ref] const" on modern Delphi
{$endif FPC_VARIANTSETVAR}
  CallDesc: PCallDesc; Params: pointer); cdecl;
// warning: Delphi OSX64 LINUX ANDROID64 expects Params := @VAList
var
  v: TVarData;
  vp: PVariant;
  t: cardinal;
  ct: TSynInvokeableVariantType;
label
  direct;
begin
  t := Source.vType;
  if t = varVariantByRef then
    NewDispInvoke(Dest, PVarData(Source.VPointer)^, calldesc, params)
  else
  begin
    TRttiVarData(v).VType := varEmpty;
    vp := @v;
    if Dest = nil then
      vp := nil;
    ct := nil;
    try
      case t of
        varDispatch,
        varAny,
        varUnknown,
        varDispatch or varByRef,
        varAny or varByRef,
        varUnknown or varByRef:
          if Assigned(VarDispProc) and
             Assigned(VarCopyProc) then
            // standard Windows ComObj unit call
            VarDispProc(vp, variant(Source), CallDesc, Params)
          else
            VarInvalidOp;
        CFirstUserType .. varTypeMask:
          begin
            ct := DocVariantType; // recognize our TDocVariant
            if t = ct.VarType then
              goto direct;
            ct := LastDispInvoke; // atomic load
            if (ct <> nil) and
               (ct.VarType = t) then
              // most calls are grouped within the same custom variant type
              goto direct;
            // FindCustomVariantType() is O(1) but has a global lock
            if FindCustomVariantType(t, TCustomVariantType(ct)) then
              if ct.InheritsFrom(TSynInvokeableVariantType) then
              begin
                // direct access of our custom variants without any temp copy
                LastDispInvoke := ct;
direct:         if Dest <> nil then
                  VarClear(PVariant(Dest)^); // no temp copy, but Dest cleanup
                ct.DispInvoke(Dest, Source, CallDesc, Params);
                Dest := nil;
              end
              else if ct.InheritsFrom(TInvokeableVariantType) then
                // use standard RTL behavior for non-mORMot custom variants
                ct.DispInvoke(pointer(vp), Source, CallDesc, Params)
              else
                VarInvalidOp
            else
              VarInvalidOp;
          end;
      else
        VarInvalidOp;
      end;
    finally
      if Dest <> nil then
      begin
        if (ct <> nil) and
           (v.VType = ct.VarType) then // don't search twice if we got it
          ct.Copy(Dest^, v, {indirect=}false)
        else
          VarCopyProc(Dest^, v);
        VarClear(vp^);
      end;
    end;
  end;
end;

const
  // _CMP2SORT[] comparison of simple types - as copied to _VARDATACMP[]
  _NUM1: array[varEmpty..varDate] of byte = (
    1, 1, 2, 3, 4, 5, 6, 7);
  _NUM2: array[varShortInt..varWord64] of byte = (
    8, 9, 10, 11, 12, 13);

procedure InitializeUnit;
var
  vm: TVariantManager; // available since Delphi 7
  vt: cardinal;
  ins: boolean;
  i: PtrUInt;
  {$ifdef FPC}
  test: variant;
  {$endif FPC}
begin
  // register the TDocVariant custom type
  DocVariantType := TDocVariant(SynRegisterCustomVariantType(TDocVariant));
  vt := DocVariantType.VarType;
  DocVariantVType := vt;
  PCardinal(@DV_FAST[dvUndefined])^ := vt;
  PCardinal(@DV_FAST[dvArray])^ := vt;
  PCardinal(@DV_FAST[dvObject])^ := vt;
  assert({%H-}SynVariantTypes[0].VarType = vt);
  PDocVariantData(@DV_FAST[dvUndefined])^.VOptions := JSON_FAST;
  PDocVariantData(@DV_FAST[dvArray])^.VOptions := JSON_FAST + [dvoIsArray];
  PDocVariantData(@DV_FAST[dvObject])^.VOptions := JSON_FAST + [dvoIsObject];
  // FPC allows to define variables with absolute JSON_[...] but Delphi doesn't
  JSON_FAST_STRICT := JSON_[mFastStrict];
  JSON_FAST_EXTENDED := JSON_[mFastExtended];
  JSON_FAST_EXTENDEDINTERN := JSON_[mFastExtendedIntern];
  JSON_NAMEVALUE := PDocVariantOptionsBool(@JSON_[mNameValue])^;
  JSON_NAMEVALUEINTERN := PDocVariantOptionsBool(@JSON_[mNameValueIntern])^;
  JSON_OPTIONS := PDocVariantOptionsBool(@JSON_[mDefault])^;
  // redirect to the feature complete variant wrapper functions
  BinaryVariantLoadAsJson := _BinaryVariantLoadAsJson;
  VariantClearSeveral := _VariantClearSeveral;
  _VariantSaveJson := @__VariantSaveJson;
  SortDynArrayVariantComp := pointer(@FastVarDataComp);
  // setup FastVarDataComp() efficient lookup comparison functions
  for ins := false to true do
  begin
    for i := low(_NUM1) to high(_NUM1) do
      _VARDATACMP[i, ins] := _NUM1[i];
    _VARDATACMP[varBoolean, ins] := 14;
    for i := low(_NUM2) to high(_NUM2) do
      _VARDATACMP[i, ins] := _NUM2[i];
  end;
  _VARDATACMP[varString, false] := 15;
  _VARDATACMP[varString, true]  := 16;
  _VARDATACMP[varOleStr, false] := 17;
  _VARDATACMP[varOleStr, true]  := 18;
  {$ifdef HASVARUSTRING}
  _VARDATACMP[varUString, false] := 17;
  _VARDATACMP[varUString, true]  := 18;
  {$endif HASVARUSTRING}
  // patch DispInvoke for performance and to circumvent RTL inconsistencies
  GetVariantManager(vm);
  vm.DispInvoke := NewDispInvoke;
  SetVariantManager(vm);
  {$ifdef FPC}
  // circumvent FPC 3.2+ inverted parameters order - may be fixed in later FPC
  test := _ObjFast([]);
  test.Add('nam', 'val'); // late binding DispInvoke() call
  DispInvokeArgOrderInverted := (_Safe(test)^.Names[0] = 'val');
  {$endif FPC}
end;


initialization
  InitializeUnit;

end.

