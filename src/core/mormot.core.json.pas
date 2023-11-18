
/// Framework Core Low-Level JSON Processing
// - this unit is a part of the Open Source Synopse mORMot framework 2,
// licensed under a MPL/GPL/LGPL three license - see LICENSE.md

/// 框架核心底层 JSON 处理
// - 该单元是开源 Synopse mORMot 框架 2 的一部分，
// 根据 MPL/GPL/LGPL 三种许可证进行许可 - 请参阅 LICENSE.md
unit mormot.core.json;

{
  *****************************************************************************

   JSON functions shared by all framework units
    - Low-Level JSON Processing Functions
    - TTextWriter class with proper JSON escaping and WriteObject() support
    - JSON-aware TSynNameValue TSynPersistentStoreJson
    - JSON-aware TSynDictionary Storage
    - JSON Unserialization for any kind of Values
    - JSON Serialization Wrapper Functions
    - Abstract Classes with Auto-Create-Fields

    所有框架单元共享的 JSON 函数
        - 低级 JSON 处理函数
        - 具有适当 JSON 转义和 WriteObject() 支持的 TTextWriter 类
        - JSON 感知 TSynNameValue TSynPersistentStoreJson
        - JSON 感知的 TSynDictionary 存储
        - 任何类型值的 JSON 反序列化
        - JSON 序列化包装函数
        - 具有自动创建字段的抽象类    

  *****************************************************************************
}

interface

{$I ..\mormot.defines.inc}

uses
  classes,
  contnrs,
  sysutils,
  {$ifndef FPC}
  typinfo, // for proper Delphi inlining 正确的 Delphi 内联
  {$endif FPC}
  mormot.core.base,
  mormot.core.os,
  mormot.core.unicode,
  mormot.core.text,
  mormot.core.datetime,
  mormot.core.rtti,
  mormot.core.buffers,
  mormot.core.data;


{ ********** Low-Level JSON Processing Functions }
{ ********** 低级 JSON 处理函数 }

type
  /// exception raised by this unit, in relation to raw JSON process
  /// 该单元引发的异常，与原始 JSON 过程相关
  EJsonException = class(ESynException);

  /// kind of first character used from JSON_TOKENS[] for efficient JSON parsing
  /// JSON_TOKENS[] 中使用的第一个字符，用于高效 JSON 解析
  TJsonToken = (
    jtNone,
    jtDoubleQuote,
    jtFirstDigit,
    jtNullFirstChar,
    jtTrueFirstChar,
    jtFalseFirstChar,
    jtObjectStart,
    jtArrayStart,
    jtObjectStop,
    jtArrayStop,
    jtAssign,
    jtComma,
    jtSingleQuote,
    jtIdentifierFirstChar,
    jtSlash);

  /// defines a lookup table used for branch-less first char JSON parsing
  /// 定义用于无分支第一个字符 JSON 解析的查找表
  TJsonTokens = array[AnsiChar] of TJsonToken;
  /// points to a lookup table used for branch-less first char JSON parsing
  /// 指向用于无分支第一个字符 JSON 解析的查找表
  PJsonTokens = ^TJsonTokens;

  /// kind of character used from JSON_CHARS[] for efficient JSON parsing
  // - using such a set compiles into TEST [MEM], IMM so is more efficient
  // than a regular set of AnsiChar which generates much slower BT [MEM], IMM
  // - the same 256-byte memory will also be reused from L1 CPU cache
  // during the parsing of complex JSON input
  // - TTestCoreProcess.JSONBenchmark shows around 900MB/s on my i5 notebook
  /// 用于高效 JSON 解析的 JSON_CHARS[]字符的种类
  // - 使用这样的字符集可编译为 TEST [MEM]，IMM，因此比普通的 AnsiChar 字符集更高效，后者生成 BT [MEM]，IMM 的速度要慢得多
  // - 在解析复杂 JSON 输入时，CPU 一级缓存中的 256 字节内存也将被重复使用
  // - TTestCoreProcess.JSONBenchmark 在我的 i5 笔记本上显示速度约为 900MB/s。
  TJsonChar = set of (
    jcJsonIdentifierFirstChar,
    jcJsonIdentifier,
    jcEndOfJsonFieldOr0,
    jcEndOfJsonFieldNotName,
    jcEndOfJsonValueField,
    jcJsonStringMarker,
    jcDigitFirstChar,
    jcDigitFloatChar);

  /// defines a lookup table used for branch-less JSON parsing
  /// 定义用于无分支 JSON 解析的查找表
  TJsonCharSet = array[AnsiChar] of TJsonChar;
  /// points to a lookup table used for branch-less JSON parsing
  /// 指向用于无分支 JSON 解析的查找表
  PJsonCharSet = ^TJsonCharSet;

const
  /// JSON_ESCAPE[] lookup value: indicates no escape needed
  /// JSON_ESCAPE[] 查找值：表示无需转义
  JSON_ESCAPE_NONE = 0;
  /// JSON_ESCAPE[] lookup value: indicates #0 (end of string)
  /// JSON_ESCAPE[] 查找值：表示 #0（字符串的结尾）
  JSON_ESCAPE_ENDINGZERO = 1;
  /// JSON_ESCAPE[] lookup value: should be escaped as \u00xx
  /// JSON_ESCAPE[] 查找值：应转义为 \u00xx
  JSON_ESCAPE_UNICODEHEX = 2;

var
  /// 256-byte lookup table for fast branchless initial character JSON parsing
  /// 用于快速无分支初始字符 JSON 解析的 256 字节查找表
  JSON_TOKENS: TJsonTokens;
  /// 256-byte lookup table for fast branchless JSON parsing
  // - to be used e.g. as:
  // ! if jvJsonIdentifier in JSON_CHARS[P^] then ...
  /// 用于快速无分支 JSON 解析的 256 字节查找表
  // - 可用作： // !
  // ! if jvJsonIdentifier in JSON_CHARS[P^] then ...  
  JSON_CHARS: TJsonCharSet;
  /// 256-byte lookup table for fast branchless JSON text escaping
  // - 0 = JSON_ESCAPE_NONE indicates no escape needed
  // - 1 = JSON_ESCAPE_ENDINGZERO indicates #0 (end of string)
  // - 2 = JSON_ESCAPE_UNICODEHEX should be escaped as \u00xx
  // - b,t,n,f,r,\," as escaped character for #8,#9,#10,#12,#13,\,"
  /// 用于快速无分支 JSON 文本转义的 256 字节查找表
  // - 0 = JSON_ESCAPE_NONE 表示无需转义
  // - 1 = JSON_ESCAPE_ENDINGZERO 表示 #0（字符串结尾）
  // - 2 = JSON_ESCAPE_UNICODEHEX 应转义为 \u00xx
  // - b,t,n,f,r,\," 作为 #8,#9,#10,#12,#13,\," 的转义字符  
  JSON_ESCAPE: array[byte] of byte;

  /// how many initial chars of a JSON array are parsed for intial capacity
  // - used e.g. by _JL_DynArray() and TDocVariantData.InitJsonInPlace()
  // - 64KB was found out empirically as a good value - but you can tune it
  /// JSON 数组的初始字符数被解析为初始容量。
  // - 用于 _JL_DynArray() 和 TDocVariantData.InitJsonInPlace() 等。
  // - 根据经验，64KB 是一个不错的值，但你可以调整它
  JSON_ARRAY_PRELOAD: integer = 65536;

/// returns TRUE if the given text buffers would be escaped when written as JSON
// - e.g. if contains " or \ characters, as defined by
// http://www.ietf.org/rfc/rfc4627.txt
/// 如果给定的文本缓冲区在写入为 JSON 时会被转义，则返回 TRUE
// - 例如如果包含 " 或 \ 字符，定义为
// http://www.ietf.org/rfc/rfc4627.txt
function NeedsJsonEscape(const Text: RawUtf8): boolean; overload;
  {$ifdef HASINLINE}inline;{$endif}

/// returns TRUE if the given text buffers would be escaped when written as JSON
// - e.g. if contains " or \ characters, as defined by
// http://www.ietf.org/rfc/rfc4627.txt
/// 如果给定的文本缓冲区在写入为 JSON 时会被转义，则返回 TRUE
// - 例如如果包含 " 或 \ 字符，定义为
// http://www.ietf.org/rfc/rfc4627.txt
function NeedsJsonEscape(P: PUtf8Char): boolean; overload;

/// returns TRUE if the given text buffers would be escaped when written as JSON
// - e.g. if contains " or \ characters, as defined by
// http://www.ietf.org/rfc/rfc4627.txt
/// 如果给定的文本缓冲区在写入为 JSON 时会被转义，则返回 TRUE
// - 例如如果包含 " 或 \ 字符，定义为
// http://www.ietf.org/rfc/rfc4627.txt
function NeedsJsonEscape(P: PUtf8Char; PLen: integer): boolean; overload;

/// UTF-8 encode one or two \u#### JSON escaped codepoints into Dest
// - P^ should point at 'u1234' just after \u1234
// - return ending P position, maybe after another \u#### UTF-16 surrogate char
/// UTF-8 将一或两个 \u#### JSON 转义代码点编码为 Dest
// - P^ 应该指向 \u1234 之后的 'u1234'
// - 返回结束 P 位置，可能在另一个 \u#### UTF-16 代理字符之后
function JsonEscapeToUtf8(var D: PUtf8Char; P: PUtf8Char): PUtf8Char;
  {$ifdef HASINLINE}inline;{$endif}

/// test if the supplied buffer is a "string" value or a numerical value
// (floating point or integer), according to the characters within
// - this version will recognize null/false/true as strings
// - e.g. IsString('0')=false, IsString('abc')=true, IsString('null')=true
/// 测试提供的缓冲区是“字符串”值还是数字值
//（浮点数或整数），根据里面的字符
// - 此版本会将 null/false/true 识别为字符串
// - 例如IsString('0')=false, IsString('abc')=true, IsString('null')=true
function IsString(P: PUtf8Char): boolean;

/// test if the supplied buffer is a "string" value or a numerical value
// (floating or integer), according to the JSON encoding schema
// - this version will NOT recognize JSON null/false/true as strings
// - e.g. IsStringJson('0')=false, IsStringJson('abc')=true,
// but IsStringJson('null')=false
// - will follow the JSON definition of number, i.e. '0123' is a string (i.e.
// '0' is excluded at the begining of a number) and '123' is not a string
/// 根据 JSON 编码模式测试提供的缓冲区是“字符串”值还是数值（浮点或整数）
// - 此版本不会将 JSON null/false/true 识别为字符串
// - 例如 IsStringJson('0')=false, IsStringJson('abc')=true, 但 IsStringJson('null')=false
// - 将遵循数字的 JSON 定义，即 '0123' 是一个字符串（即在数字开头排除 '0'），而 '123' 不是字符串
function IsStringJson(P: PUtf8Char): boolean;

/// test if the supplied text buffer is a correct JSON value
/// 测试提供的文本缓冲区是否是正确的 JSON 值
function IsValidJson(P: PUtf8Char; len: PtrInt): boolean; overload;

/// test if the supplied text is a correct JSON value
/// 测试提供的文本是否是正确的 JSON 值
function IsValidJson(const s: RawUtf8): boolean; overload;

/// test if the supplied buffer is a correct JSON value
// - won't check the supplied length, so is likely to be faster than overloads
/// 测试提供的缓冲区是否是正确的 JSON 值
// - 不会检查提供的长度，因此可能比重载更快
function IsValidJsonBuffer(P: PUtf8Char): boolean;

/// simple method to go after the next ',' character
/// 清除下一个", "字符的简单方法
procedure IgnoreComma(var P: PUtf8Char);
  {$ifdef HASINLINE}inline;{$endif}

/// returns TRUE if the given text buffer contains simple characters as
// recognized by JSON extended syntax
// - follow GetJsonPropName and GotoNextJsonObjectOrArray expectations
/// 如果给定文本缓冲区包含 JSON 扩展语法识别的简单字符，则返回 TRUE
// - 遵循 GetJsonPropName 和 GotoNextJsonObjectOrArray 期望
function JsonPropNameValid(P: PUtf8Char): boolean;
  {$ifdef HASINLINE}inline;{$endif}

/// decode a JSON field value in-place from an UTF-8 encoded text buffer
// - this function decodes in the P^ buffer memory itself (no memory allocation
// or copy), for faster process - so take care that P^ is not shared
// - works for both field names or values (e.g. '"FieldName":' or 'Value,')
// - EndOfObject (if not nil) is set to the JSON value char (',' ':' or '}' e.g.)
// - optional WasString is set to true if the JSON value was a JSON "string"
// - returns a PUtf8Char to the decoded value, with its optional length in Len^
// - '"strings"' are decoded as 'strings', with WasString=true, properly JSON
// unescaped (e.g. any \u0123 pattern would be converted into UTF-8 content)
// - null is decoded as nil, with WasString=false
// - true/false boolean values are returned as 'true'/'false', with WasString=false
// - any number value is returned as its ascii representation, with WasString=false
// - PDest points to the next field to be decoded, or nil on JSON parsing error
/// 从 UTF-8 编码的文本缓冲区就地解码 JSON 字段值
//- 该函数在 P^ 缓冲区内存中解码（不分配或复制内存），以加快处理速度，因此请注意 P^ 不是共享的。
// - 对字段名或值都有效（例如""FieldName": "或 "Value,"）。
// - EndOfObject（如果不是 nil）被设置为 JSON 值 char（例如',' ':' 或 '}')
// - 如果 JSON 值是一个 JSON "字符串"，可选的 WasString 将被设置为 true
// - 返回解码值的 PUtf8Char，长度以 Len^ 为单位可选
// - '"字符串 "被解码为 "字符串"，WasString=true，正确的 JSON 解码（例如，任何 \u0123 模式将被转换为 UTF-8 内容）。
// - 空会被解码为 nil，WasString=false。
// - 真/假布尔值以 "true"/"false "返回，WasString=false
// - 在 WasString=false 时，任何数字值都以 ascii 表示形式返回。
// - PDest 指向下一个要解码的字段，或在 JSON 解析错误时为 nil
function GetJsonField(P: PUtf8Char; out PDest: PUtf8Char;
  WasString: PBoolean = nil; EndOfObject: PUtf8Char = nil;
  Len: PInteger = nil): PUtf8Char;

/// decode a JSON field name in an UTF-8 encoded buffer
// - this function decodes in the P^ buffer memory itself (no memory allocation
// or copy), for faster process - so take care that P^ is not shared
// - it will return the property name (with an ending #0) or nil on error
// - this function will handle strict JSON property name (i.e. a "string"), but
// also MongoDB extended syntax, e.g. {age:{$gt:18}} or {'people.age':{$gt:18}}
// see @http://docs.mongodb.org/manual/reference/mongodb-extended-json
/// 在 UTF-8 编码的缓冲区中解码 JSON 字段名称
// - 该函数在 P^ 缓冲区内存中解码（无内存分配或复制），以加快处理速度，因此请注意 P^ 不是共享的。
// - 出错时将返回属性名称（以 #0 结尾）或 nil
// - 该函数将处理严格的 JSON 属性名（即 "字符串"），但也会处理 MongoDB 扩展语法，例如 {age:{$gt:18}} 或 {'people.age':{$gt:18}}
// 参见 @http://docs.mongodb.org/manual/reference/mongodb-extended-json
function GetJsonPropName(var Json: PUtf8Char; Len: PInteger = nil): PUtf8Char; overload;

/// decode a JSON field name in an UTF-8 encoded shortstring variable
// - this function would left the P^ buffer memory untouched, so may be safer
// than the overloaded GetJsonPropName() function in some cases
// - it will return the property name as a local UTF-8 encoded shortstring,
// or PropName='' on error
// - this function won't unescape the property name, as strict JSON (i.e. a "st\"ring")
// - but it will handle MongoDB syntax, e.g. {age:{$gt:18}} or {'people.age':{$gt:18}}
// see @http://docs.mongodb.org/manual/reference/mongodb-extended-json
/// 以 UTF-8 编码的短字符串变量解码 JSON 字段名称
// - 该函数将不触及 P^ 缓冲区内存，因此在某些情况下可能比重载的 GetJsonPropName() 函数更安全
// - 它将以本地 UTF-8 编码短字符串的形式返回属性名，或在出错时返回 PropName=''。
// - 作为严格的 JSON（即一个 "st\"ring"），该函数不会解码属性名
// - 但它会处理 MongoDB 语法，例如 {age:{$gt:18}} 或 {'people.age':{$gt:18}}
// 参见 @http://docs.mongodb.org/manual/reference/mongodb-extended-json
procedure GetJsonPropName(var P: PUtf8Char; out PropName: shortstring); overload;

/// decode a JSON content in an UTF-8 encoded buffer
// - GetJsonField() will only handle JSON "strings" or numbers - if
// HandleValuesAsObjectOrArray is TRUE, this function will process JSON {
// objects } or [ arrays ] and add a #0 at the end of it
// - decodes in the Json^ buffer memory itself (no memory allocation nor copy)
// for faster process - so take care that it is an unique string
// - returns a pointer to the value start, and moved Json to the next field to
// be decoded, or Json=nil in case of any unexpected input
// - WasString is set to true if the JSON value was a "string"
// - EndOfObject (if not nil) is set to the JSON value end char (',' ':' or '}')
// - if Len is set, it will contain the length of the returned pointer value
/// 解码 UTF-8 编码缓冲区中的 JSON 内容
// - GetJsonField() 将仅处理 JSON“字符串”或数字 - 如果 HandleValuesAsObjectOrArray 为 TRUE，则此函数将处理 JSON {objects } 或 [ arrays ] 并在其末尾添加 #0
// - 在 Json^ 缓冲存储器本身中进行解码（没有内存分配或复制）以加快处理速度 - 所以请注意它是一个唯一的字符串
// - 返回指向值 start 的指针，并将 Json 移动到下一个要解码的字段，或者在出现任何意外输入时 Json=nil
// - 如果 JSON 值是“字符串”，则 WasString 设置为 true
// - EndOfObject（如果不是 nil）设置为 JSON 值 end char（',' ':' 或 '}'）
// - 如果设置了 Len，它将包含返回的指针值的长度
function GetJsonFieldOrObjectOrArray(var Json: PUtf8Char;
  WasString: PBoolean = nil; EndOfObject: PUtf8Char = nil;
  HandleValuesAsObjectOrArray: boolean = false;
  NormalizeBoolean: boolean = true; Len: PInteger = nil): PUtf8Char;

/// retrieve the next JSON item as a RawJson variable
// - buffer can be either any JSON item, i.e. a string, a number or even a
// JSON array (ending with ]) or a JSON object (ending with })
// - EndOfObject (if not nil) is set to the JSON value end char (',' ':' or '}')
/// 以 RawJson 变量的形式获取下一个 JSON 项目
// - 缓冲区可以是任何 JSON 项目，即字符串、数字甚至 JSON 数组（以 ] 结尾）或 JSON 对象（以 } 结尾）
// - EndOfObject（如果不是 nil）将被设置为 JSON 值 end char（','':'或'}'）。
procedure GetJsonItemAsRawJson(var P: PUtf8Char; var result: RawJson;
  EndOfObject: PAnsiChar = nil);

/// retrieve the next JSON item as a RawUtf8 decoded buffer
// - buffer can be either any JSON item, i.e. a string, a number or even a
// JSON array (ending with ]) or a JSON object (ending with })
// - EndOfObject (if not nil) is set to the JSON value end char (',' ':' or '}')
// - just call GetJsonField(), and create a new RawUtf8 from the returned value,
// after proper unescape if WasString^=true
/// 检索下一个 JSON 项目作为 RawUtf8 解码缓冲区
// - buffer 可以是任何 JSON 项，即字符串、数字甚至 JSON 数组（以 ] 结尾）或 JSON 对象（以 } 结尾）
// - EndOfObject（如果不是 nil）设置为 JSON 值 end char（',' ':' 或 '}'）
// - 只需调用 GetJsonField()，并在正确转义后根据返回值创建一个新的 RawUtf8（如果 WasString^=true）
function GetJsonItemAsRawUtf8(var P: PUtf8Char; var output: RawUtf8;
  WasString: PBoolean = nil; EndOfObject: PUtf8Char = nil): boolean;

/// read the position of the JSON value just after a property identifier
// - this function will handle strict JSON property name (i.e. a "string"), but
// also MongoDB extended syntax, e.g. {age:{$gt:18}} or {'people.age':{$gt:18}}
// see @http://docs.mongodb.org/manual/reference/mongodb-extended-json
/// 读取属性标识符后面的 JSON 值的位置
// - 该函数将处理严格的 JSON 属性名称（即“字符串”），但也处理 MongoDB 扩展语法，例如 {年龄:{$gt:18}} 或 {'people.age':{$gt:18}}
// 请参阅@http://docs.mongodb.org/manual/reference/mongodb-extended-json
function GotoNextJsonPropName(P: PUtf8Char; tab: PJsonCharSet): PUtf8Char;
  {$ifdef FPC} inline; {$endif}

/// get the next character after a quoted buffer
// - the first character in P^ must be "
// - it will return the latest " position, ignoring \" within
// - caller should check that return PUtf8Char is indeed a "
/// 获取带引号的缓冲区后的下一个字符
// - P^ 中的第一个字符必须是“
// - 它将返回最新的“位置，忽略其中的\”
// - 调用者应该检查返回的 PUtf8Char 确实是一个“
function GotoEndOfJsonString(P: PUtf8Char): PUtf8Char;

/// reach positon just after the current JSON item in the supplied UTF-8 buffer
// - buffer can be either any JSON item, i.e. a string, a number or even a
// JSON array (ending with ]) or a JSON object (ending with })
// - returns nil if the specified buffer is not valid JSON content
// - returns the position in buffer just after the item excluding the separator
// character - i.e. result^ may be ',','}',']'
// - for speed, numbers and true/false/null constant won't be exactly checked,
// and MongoDB extended syntax like {age:{$gt:18}} will be allowed - so you
// may consider GotoEndJsonItemStrict() if you expect full standard JSON parsing
/// 到达所提供的 UTF-8 缓冲区中当前 JSON 项之后的位置
// - buffer 可以是任何 JSON 项，即字符串、数字甚至 JSON 数组（以 ] 结尾）或 JSON 对象（以 } 结尾）
// - 如果指定的缓冲区不是有效的 JSON 内容，则返回 nil
// - 返回缓冲区中不包括分隔符的项目之后的位置 - 即结果^可能是 ',','}',']'
// - 对于速度，数字和 true/false/null 常量不会被精确检查，并且将允许像 {age:{$gt:18}} 这样的 MongoDB 扩展语法 - 所以如果您期望的话，您可以考虑 GotoEndJsonItemStrict() 完整标准 JSON 解析
function GotoEndJsonItem(P: PUtf8Char; PMax: PUtf8Char = nil): PUtf8Char;

/// fast JSON parsing function - for internal inlined use e.g. by GotoEndJsonItem
/// 快速 JSON 解析函数 - 用于内部内联使用，例如 通过 GotoEndJsonItem
function GotoEndJsonItemFast(P, PMax: PUtf8Char
  {$ifndef CPUX86NOTPIC}; tab: PJsonCharSet{$endif}): PUtf8Char;
  {$ifdef FPC}inline;{$endif}

/// reach positon just after the current JSON item in the supplied UTF-8 buffer
// - in respect to GotoEndJsonItem(), this function will validate for strict
// JSON simple values, i.e. real numbers or only true/false/null constants,
// and refuse MongoDB extended syntax like {age:{$gt:18}}
/// 到达所提供的 UTF-8 缓冲区中当前 JSON 项之后的位置
// - 对于 GotoEndJsonItem()，此函数将验证严格的 JSON 简单值，即实数或仅 true/false/null 常量，并拒绝 MongoDB 扩展语法，如 {age:{$gt:18}}
function GotoEndJsonItemStrict(P: PUtf8Char): PUtf8Char;

/// reach the positon of the next JSON item in the supplied UTF-8 buffer
// - buffer can be either any JSON item, i.e. a string, a number or even a
// JSON array (ending with ]) or a JSON object (ending with })
// - returns nil if the specified number of items is not available in buffer
// - returns the position in buffer after the item including the separator
// character (optionally in EndOfObject) - i.e. result will be at the start of
// the next object, and EndOfObject may be ',','}',']'
/// 到达提供的 UTF-8 缓冲区中下一个 JSON 项的位置
// - buffer 可以是任何 JSON 项，即字符串、数字甚至 JSON 数组（以 ] 结尾）或 JSON 对象（以 } 结尾）
// - 如果指定数量的项目在缓冲区中不可用，则返回 nil
// - 返回缓冲区中包含分隔符的项目之后的位置（可选地在 EndOfObject 中） - 即结果将位于下一个对象的开头，EndOfObject 可能是 ',','}',']'
function GotoNextJsonItem(P: PUtf8Char; NumberOfItemsToJump: cardinal = 1;
  EndOfObject: PAnsiChar = nil): PUtf8Char;

/// reach the position of the next JSON object of JSON array
// - first char is expected to be either '[' or '{'
// - will return nil in case of parsing error or unexpected end (#0)
// - will return the next character after ending ] or } - i.e. may be , } ]
/// 到达 JSON 数组的下一个 JSON 对象的位置
// - 第一个字符应该是 '[' 或 '{'
// - 如果出现解析错误或意外结束，将返回 nil (#0)
// - 将返回结束 ] 或 } 后的下一个字符 - 即可能是 , } ]
function GotoNextJsonObjectOrArray(P: PUtf8Char): PUtf8Char; overload;
  {$ifdef FPC}inline;{$endif}

/// reach the position of the next JSON object of JSON array
// - first char is expected to be just after the initial '[' or '{'
// - specify ']' or '}' as the expected EndChar
// - will return nil in case of parsing error or unexpected end (#0)
// - will return the next character after ending ] or } - i.e. may be , } ]
/// 到达 JSON 数组的下一个 JSON 对象的位置
// - 第一个字符预计位于初始“[”或“{”之后
// - 指定 ']' 或 '}' 作为预期的 EndChar
// - 如果出现解析错误或意外结束，将返回 nil (#0)
// - 将返回结束 ] 或 } 后的下一个字符 - 即可能是 , } ]
function GotoNextJsonObjectOrArray(P: PUtf8Char; EndChar: AnsiChar): PUtf8Char; overload;
  {$ifdef FPC}inline;{$endif}

/// reach the position of the next JSON object of JSON array
// - first char is expected to be either '[' or '{'
// - this version expects a maximum position in PMax: it may be handy to break
// the parsing for HUGE content - used e.g. by JsonArrayCount(P,PMax)
// - will return nil in case of parsing error or if P reached PMax limit
// - will return the next character after ending ] or { - i.e. may be , } ]
/// 到达 JSON 数组的下一个 JSON 对象的位置
// - 第一个字符应该是 '[' 或 '{'
// - 这个版本期望 PMax 中的最大位置：它可能很容易打破对巨大内容的解析 - 例如使用 通过 JsonArrayCount(P,PMax)
// - 如果出现解析错误或 P 达到 PMax 限制，将返回 nil
// - 将返回结束 ] 或 { - 即可能是 , } ] 后的下一个字符
function GotoNextJsonObjectOrArrayMax(P, PMax: PUtf8Char): PUtf8Char;
  {$ifdef FPC}inline;{$endif}

/// search the EndOfObject of a JSON buffer, just like GetJsonField() does
/// 搜索 JSON 缓冲区的 EndOfObject，就像 GetJsonField() 一样
function ParseEndOfObject(P: PUtf8Char; out EndOfObject: AnsiChar): PUtf8Char;
  {$ifdef HASINLINE}inline;{$endif}

/// compute the number of elements of a JSON array
// - this will handle any kind of arrays, including those with nested
// JSON objects or arrays
// - incoming P^ should point to the first char AFTER the initial '[' (which
// may be a closing ']')
// - returns -1 if the supplied input is invalid, or the number of identified
// items in the JSON array buffer
/// 计算 JSON 数组的元素数量
// - 这将处理任何类型的数组，包括具有嵌套 JSON 对象或数组的数组
// - 传入的 P^ 应指向初始“[”（可能是结束“]”之后的第一个字符）
// - 如果提供的输入无效，或者 JSON 数组缓冲区中已识别项目的数量，则返回 -1
function JsonArrayCount(P: PUtf8Char): integer; overload;

/// compute the number of elements of a JSON array
// - this will handle any kind of arrays, including those with nested
// JSON objects or arrays
// - incoming P^ should point to the first char after the initial '[' (which
// may be a closing ']')
// - this overloaded method will abort if P reaches a certain position, and
// return the current counted number of items as negative, which could be used
// as initial allocation before the loop - typical use in this case is e.g.
// ! cap := abs(JsonArrayCount(P, P + JSON_ARRAY_PRELOAD));
/// 计算 JSON 数组的元素数量
// - 这将处理任何类型的数组，包括具有嵌套 JSON 对象或数组的数组
// - 传入的 P^ 应指向初始“[”（可能是结束“]”之后的第一个字符）
// - 如果 P 到达某个位置，此重载方法将中止，并将当前计数的项目数返回为负数，这可以用作循环之前的初始分配 - 这种情况下的典型用途是例如：
! cap := abs(JsonArrayCount(P, P + JSON_ARRAY_PRELOAD));
function JsonArrayCount(P, PMax: PUtf8Char): integer; overload;

/// go to the #nth item of a JSON array
// - implemented via a fast SAX-like approach: the input buffer is not changed,
// nor no memory buffer allocated neither content copied
// - returns nil if the supplied index is out of range
// - returns a pointer to the index-nth item in the JSON array (first index=0)
// - this will handle any kind of arrays, including those with nested
// JSON objects or arrays
// - incoming P^ should point to the first initial '[' char
/// 转到 JSON 数组的第 #n 项
// - 通过类似 SAX 的快速方法实现：输入缓冲区未更改，也未分配内存缓冲区，也未复制内容
// - 如果提供的索引超出范围，则返回 nil
// - 返回指向 JSON 数组中第 n 个索引项的指针（第一个索引=0）
// - 这将处理任何类型的数组，包括具有嵌套 JSON 对象或数组的数组
// - 传入的 P^ 应指向第一个初始 '[' 字符
function JsonArrayItem(P: PUtf8Char; Index: integer): PUtf8Char;

/// retrieve the positions of all elements of a JSON array
// - this will handle any kind of arrays, including those with nested
// JSON objects or arrays
// - incoming P^ should point to the first char AFTER the initial '[' (which
// may be a closing ']')
// - returns false if the supplied input is invalid
// - returns true on success, with Values[] pointing to each unescaped value,
// may be a JSON string, object, array of constant
/// 检索 JSON 数组中所有元素的位置
// - 这将处理任何类型的数组，包括具有嵌套 JSON 对象或数组的数组
// - 传入的 P^ 应指向初始“[”（可能是结束“]”之后的第一个字符）
// - 如果提供的输入无效，则返回 false
// - 成功时返回 true，Values[] 指向每个未转义的值，可以是 JSON 字符串、对象、常量数组
function JsonArrayDecode(P: PUtf8Char;
  out Values: TPUtf8CharDynArray): boolean;

/// compute the number of fields in a JSON object
// - this will handle any kind of objects, including those with nested JSON
// objects or arrays, and also the MongoDB extended syntax of property names
// - incoming P^ should point to the first char after the initial '{' (which
// may be a closing '}')
// - returns -1 if the input was not a proper JSON object
/// 计算 JSON 对象中的字段数
// - 这将处理任何类型的对象，包括具有嵌套 JSON 对象或数组的对象，以及属性名称的 MongoDB 扩展语法
// - 传入的 P^ 应指向初始“{”之后的第一个字符（可能是结束的“}”）
// - 如果输入不是正确的 JSON 对象，则返回 -1
function JsonObjectPropCount(P: PUtf8Char): integer;

/// go to a named property of a JSON object
// - implemented via a fast SAX-like approach: the input buffer is not changed,
// nor no memory buffer allocated neither content copied
// - returns nil if the supplied property name does not exist
// - returns a pointer to the matching item in the JSON object
// - this will handle any kind of objects, including those with nested
// JSON objects or arrays
// - incoming P^ should point to the first initial '{' char
/// 转到 JSON 对象的命名属性
// - 通过类似 SAX 的快速方法实现：输入缓冲区未更改，也未分配内存缓冲区，也未复制内容
// - 如果提供的属性名称不存在，则返回 nil
// - 返回指向 JSON 对象中匹配项的指针
// - 这将处理任何类型的对象，包括那些具有嵌套 JSON 对象或数组的对象
// - 传入的 P^ 应指向第一个初始 '{' 字符
function JsonObjectItem(P: PUtf8Char; const PropName: RawUtf8;
  PropNameFound: PRawUtf8 = nil): PUtf8Char;

/// go to a property of a JSON object, by its full path, e.g. 'parent.child'
// - implemented via a fast SAX-like approach: the input buffer is not changed,
// nor no memory buffer allocated neither content copied
// - returns nil if the supplied property path does not exist
// - returns a pointer to the matching item in the JSON object
// - this will handle any kind of objects, including those with nested
// JSON objects or arrays
// - incoming P^ should point to the first initial '{' char
/// 通过完整路径转到 JSON 对象的属性，例如 '父母.孩子'
// - 通过类似 SAX 的快速方法实现：输入缓冲区未更改，也未分配内存缓冲区，也未复制内容
// - 如果提供的属性路径不存在则返回 nil
// - 返回指向 JSON 对象中匹配项的指针
// - 这将处理任何类型的对象，包括那些具有嵌套 JSON 对象或数组的对象
// - 传入的 P^ 应指向第一个初始 '{' 字符
function JsonObjectByPath(JsonObject, PropPath: PUtf8Char): PUtf8Char;

/// return all matching properties of a JSON object
// - here the PropPath could be a comma-separated list of full paths,
// e.g. 'Prop1,Prop2' or 'Obj1.Obj2.Prop1,Obj1.Prop2'
// - returns '' if no property did match
// - returns a JSON object of all matching properties
// - this will handle any kind of objects, including those with nested
// JSON objects or arrays
// - incoming P^ should point to the first initial '{' char
/// 返回 JSON 对象的所有匹配属性
// - 这里的 PropPath 可以是以逗号分隔的完整路径列表，例如： “Prop1，Prop2”或“Obj1.Obj2.Prop1，Obj1.Prop2”
// - 如果没有属性匹配则返回 ''
// - 返回所有匹配属性的 JSON 对象
// - 这将处理任何类型的对象，包括那些具有嵌套 JSON 对象或数组的对象
// - 传入的 P^ 应指向第一个初始 '{' 字符
function JsonObjectsByPath(JsonObject, PropPath: PUtf8Char): RawUtf8;

/// convert one JSON object into two JSON arrays of keys and values
// - i.e. makes the following transformation:
// $ {key1:value1,key2,value2...} -> [key1,key2...] + [value1,value2...]
// - this function won't allocate any memory during its process, nor
// modify the JSON input buffer
// - is the reverse of the TTextWriter.AddJsonArraysAsJsonObject() method
// - used e.g. by TSynDictionary.LoadFromJson
// - returns the number of items parsed and stored into keys/values, -1 on
// error parsing the input JSON buffer
/// 将一个 JSON 对象转换为两个键和值的 JSON 数组
// - 即进行以下转换：
// $ {key1:value1,key2,value2...} -> [key1,key2...] + [value1,value2...]
// - 该函数在其处理过程中不会分配任何内存，也不会修改 JSON 输入缓冲区
// - 与 TTextWriter.AddJsonArraysAsJsonObject() 方法相反
// - 例如使用 通过 TSynDictionary.LoadFromJson
// - 返回已解析并存储到键/值中的项目数，如果解析输入 JSON 缓冲区出错，则返回 -1
function JsonObjectAsJsonArrays(Json: PUtf8Char;
  out keys, values: RawUtf8): integer;

/// remove comments and trailing commas from a text buffer before passing
// it to a JSON parser
// - handle two types of comments: starting from // till end of line
// or /* ..... */ blocks anywhere in the text content
// - trailing commas is replaced by ' ', so resulting JSON is valid for parsers
// what not allows trailing commas (browsers for example)
// - may be used to prepare configuration files before loading;
// for example we store server configuration in file config.json and
// put some comments in this file then code for loading is:
// !var cfg: RawUtf8;
// !  cfg := StringFromFile(ExtractFilePath(paramstr(0))+'Config.json');
// !  RemoveCommentsFromJson(@cfg[1]);
// !  pLastChar := JsonToObject(sc,pointer(cfg),configValid);
/// 在将文本缓冲区传递给 JSON 解析器之前删除注释和尾随逗号
// - 处理两种类型的注释：从 // 开始直到行尾或 /* ..... */ 阻止文本内容中的任何位置
// - 尾随逗号被 ' ' 替换，因此生成的 JSON 对于不允许尾随逗号的解析器有效（例如浏览器）
// - 可用于在加载之前准备配置文件；
// 例如，我们将服务器配置存储在文件 config.json 中，并在该文件中添加一些注释，则加载代码为：
// !var cfg: RawUtf8;
// !  cfg := StringFromFile(ExtractFilePath(paramstr(0))+'Config.json');
// !  RemoveCommentsFromJson(@cfg[1]);
// !  pLastChar := JsonToObject(sc,pointer(cfg),configValid);
procedure RemoveCommentsFromJson(P: PUtf8Char); overload;

/// remove comments from a text buffer before passing it to JSON parser
// - won't remove the comments in-place, but allocate a new string
/// 在将文本缓冲区传递给 JSON 解析器之前删除注释
// - 不会就地删除注释，而是分配一个新字符串
function RemoveCommentsFromJson(const s: RawUtf8): RawUtf8; overload;

/// helper to retrieve the bit mapped integer value of a set from its JSON text
// - Names and MaxValue should be retrieved from RTTI
// - if supplied P^ is a JSON integer number, will read it directly
// - if P^ maps some ["item1","item2"] content, would fill all matching bits
// - if P^ contains ['*'], would fill all bits
// - returns P=nil if reached prematurely the end of content, or returns
// the value separator (e.g. , or }) in EndOfObject (like GetJsonField)
/// 从 JSON 文本中检索集合的位映射整数值的帮助器
// - 应从 RTTI 检索名称和 MaxValue
// - 如果提供的 P^ 是 JSON 整数，将直接读取它
// - 如果 P^ 映射一些 ["item1","item2"] 内容，将填充所有匹配位
// - 如果 P^ 包含 ['*']，将填充所有位
// - 如果提前到达内容末尾，则返回 P=nil，或者返回 EndOfObject 中的值分隔符（例如，或 }）（如 GetJsonField）
function GetSetNameValue(Names: PShortString; MaxValue: integer;
  var P: PUtf8Char; out EndOfObject: AnsiChar): QWord; overload;

/// helper to retrieve the bit mapped integer value of a set from its JSON text
// - overloaded function using the RTTI
/// 从 JSON 文本中检索集合的位映射整数值的帮助器
// - 使用 RTTI 的重载函数
function GetSetNameValue(Info: PRttiInfo;
  var P: PUtf8Char; out EndOfObject: AnsiChar): QWord; overload;

type
  /// points to one value of raw UTF-8 content, decoded from a JSON buffer
  // - used e.g. by JsonDecode() overloaded function to returns names/values
  /// 指向从 JSON 缓冲区解码的原始 UTF-8 内容的一个值
  // - 例如使用 通过 JsonDecode() 重载函数返回名称/值  
  TValuePUtf8Char = object
  public
    /// a pointer to the actual UTF-8 text
    /// 指向实际UTF-8文本的指针
    Value: PUtf8Char;
    /// how many UTF-8 bytes are stored in Value
    /// Value中存储了多少UTF-8字节
    ValueLen: PtrInt;
    /// convert the value into a UTF-8 string
    /// 将值转换为UTF-8字符串
    procedure ToUtf8(var Text: RawUtf8); overload;
      {$ifdef HASINLINE}inline;{$endif}
    /// convert the value into a UTF-8 string
    /// 将值转换为UTF-8字符串
    function ToUtf8: RawUtf8; overload;
      {$ifdef HASINLINE}inline;{$endif}
    /// convert the value into a VCL/generic string
    /// 将值转换为VCL/通用字符串
    function ToString: string;
      {$ifdef HASINLINE}inline;{$endif}
    /// convert the value into a signed integer
    /// 将值转换为有符号整数
    function ToInteger: PtrInt;
      {$ifdef HASINLINE}inline;{$endif}
    /// convert the value into an unsigned integer
    /// 将值转换为无符号整数
    function ToCardinal: PtrUInt;
      {$ifdef HASINLINE}inline;{$endif}
    /// convert the ISO-8601 text value as TDateTime
    // - could have been written e.g. by DateTimeToIso8601Text()
    /// 将 ISO-8601 文本值转换为 TDateTime
    // - 可以写成例如 通过 DateTimeToIso8601Text()    
    function Iso8601ToDateTime: TDateTime;
      {$ifdef HASINLINE}inline;{$endif}
    /// will call IdemPropNameU() over the stored text Value
    /// 将通过存储的文本值调用 IdemPropNameU()
    function Idem(const Text: RawUtf8): boolean;
      {$ifdef HASINLINE}inline;{$endif}
  end;
  /// used e.g. by JsonDecode() overloaded function to returns values
  /// 使用例如 通过 JsonDecode() 重载函数返回值
  TValuePUtf8CharArray =
    array[0 .. maxInt div SizeOf(TValuePUtf8Char) - 1] of TValuePUtf8Char;
  PValuePUtf8CharArray = ^TValuePUtf8CharArray;

  /// store one name/value pair of raw UTF-8 content, from a JSON buffer
  // - used e.g. by JsonDecode() overloaded function or UrlEncodeJsonObject()
  // to returns names/values
  /// 从 JSON 缓冲区存储原始 UTF-8 内容的一对名称/值
  // - 例如使用 通过 JsonDecode() 重载函数或 UrlEncodeJsonObject() 返回名称/值  
  TNameValuePUtf8Char = record
    /// a pointer to the actual UTF-8 name text
    /// 指向实际 UTF-8 名称文本的指针
    Name: PUtf8Char;
    /// a pointer to the actual UTF-8 value text
    /// 指向实际 UTF-8 值文本的指针
    Value: PUtf8Char;
    /// how many UTF-8 bytes are stored in Name (should be integer, not PtrInt)
    /// Name中存储了多少UTF-8字节（应该是整数，而不是PtrInt）
    NameLen: integer;
    /// how many UTF-8 bytes are stored in Value
    /// Value中存储了多少UTF-8字节
    ValueLen: integer;
  end;

  /// used e.g. by JsonDecode() overloaded function to returns name/value pairs
  /// 使用例如 通过 JsonDecode() 重载函数返回名称/值对
  TNameValuePUtf8CharDynArray = array of TNameValuePUtf8Char;

/// decode the supplied UTF-8 JSON content for the supplied names
// - data will be set in Values, according to the Names supplied e.g.
// ! JsonDecode(JSON,['name','year'],@Values) -> Values[0].Value='John'; Values[1].Value='1972';
// - if any supplied name wasn't found its corresponding Values[] will be nil
// - this procedure will decode the JSON content in-memory, i.e. the PUtf8Char
// array is created inside JSON, which is therefore modified: make a private
// copy first if you want to reuse the JSON content
// - if HandleValuesAsObjectOrArray is TRUE, then this procedure will handle
// JSON arrays or objects
// - support enhanced JSON syntax, e.g. '{name:'"John",year:1972}' is decoded
// just like '{"name":'"John","year":1972}'
/// 对提供的名称解码提供的 UTF-8 JSON 内容
// - 数据将根据提供的名称在值中设置，例如
// ! JsonDecode(JSON,['name','year'],@Values) -> Values[0].Value='John'; Values[1].Value='1972';
// - 如果未找到任何提供的名称，则其相应的 Values[] 将为 nil
// - 此过程将解码内存中的 JSON 内容，即 PUtf8Char 数组是在 JSON 中创建的，因此要进行修改：如果要重用 JSON 内容，请先制作一个私有副本
// - 如果 HandleValuesAsObjectOrArray 为 TRUE，则此过程将处理 JSON 数组或对象
// - 支持增强的 JSON 语法，例如 '{name:'"John",year:1972}' 的解码就像 '{"name":'"John","year":1972}'
procedure JsonDecode(var Json: RawUtf8; const Names: array of RawUtf8;
  Values: PValuePUtf8CharArray;
  HandleValuesAsObjectOrArray: boolean = false); overload;

/// decode the supplied UTF-8 JSON content for the supplied names
// - an overloaded function when the JSON is supplied as a RawJson variable
/// 对提供的名称解码提供的 UTF-8 JSON 内容
// - 当 JSON 作为 RawJson 变量提供时的重载函数
procedure JsonDecode(var Json: RawJson; const Names: array of RawUtf8;
  Values: PValuePUtf8CharArray;
  HandleValuesAsObjectOrArray: boolean = false); overload;

/// decode the supplied UTF-8 JSON content for the supplied names
// - data will be set in Values, according to the Names supplied e.g.
// ! JsonDecode(P,['name','year'],Values) -> Values[0]^='John'; Values[1]^='1972';
// - if any supplied name wasn't found its corresponding Values[] will be nil
// - this procedure will decode the JSON content in-memory, i.e. the PUtf8Char
// array is created inside P, which is therefore modified: make a private
// copy first if you want to reuse the JSON content
// - if HandleValuesAsObjectOrArray is TRUE, then this procedure will handle
// JSON arrays or objects
// - if ValuesLen is set, ValuesLen[] will contain the length of each Values[]
// - returns a pointer to the next content item in the JSON buffer
/// 对提供的名称解码提供的 UTF-8 JSON 内容
// - 数据将根据提供的名称在值中设置，例如
// ! JsonDecode(P,['name','year'],Values) -> Values[0]^='John'; Values[1]^='1972';
// - 如果未找到任何提供的名称，则其相应的 Values[] 将为 nil
// - 此过程将解码内存中的 JSON 内容，即 PUtf8Char 数组是在 P 内部创建的，因此进行修改：如果要重用 JSON 内容，请先制作一个私有副本
// - 如果 HandleValuesAsObjectOrArray 为 TRUE，则此过程将处理 JSON 数组或对象
// - 如果设置了 ValuesLen，ValuesLen[] 将包含每个 Values[] 的长度
// - 返回指向 JSON 缓冲区中下一个内容项的指针
function JsonDecode(P: PUtf8Char; const Names: array of RawUtf8;
  Values: PValuePUtf8CharArray;
  HandleValuesAsObjectOrArray: boolean = false): PUtf8Char; overload;

/// decode the supplied UTF-8 JSON content into an array of name/value pairs
// - this procedure will decode the JSON content in-memory, i.e. the PUtf8Char
// array is created inside JSON, which is therefore modified: make a private
// copy first if you want to reuse the JSON content
// - the supplied JSON buffer should stay available until Name/Value pointers
// from returned Values[] are accessed
// - if HandleValuesAsObjectOrArray is TRUE, then this procedure will handle
// JSON arrays or objects
// - support enhanced JSON syntax, e.g. '{name:'"John",year:1972}' is decoded
// just like '{"name":'"John","year":1972}'
/// 将提供的 UTF-8 JSON 内容解码为名称/值对数组
// - 此过程将解码内存中的 JSON 内容，即 PUtf8Char 数组是在 JSON 中创建的，因此要进行修改：如果要重用 JSON 内容，请先制作一个私有副本
// - 提供的 JSON 缓冲区应保持可用，直到访问返回的 Values[] 中的名称/值指针
// - 如果 HandleValuesAsObjectOrArray 为 TRUE，则此过程将处理 JSON 数组或对象
// - 支持增强的 JSON 语法，例如 '{name:'"John",year:1972}' 的解码就像 '{"name":'"John","year":1972}'
function JsonDecode(P: PUtf8Char; out Values: TNameValuePUtf8CharDynArray;
  HandleValuesAsObjectOrArray: boolean = false): PUtf8Char; overload;

/// decode the supplied UTF-8 JSON content for the one supplied name
// - this function will decode the JSON content in-memory, so will unescape it
// in-place: it must be called only once with the same JSON data
/// 解码所提供的 UTF-8 JSON 内容以获取所提供的名称
// - 此函数将解码内存中的 JSON 内容，因此将就地对其进行转义：必须使用相同的 JSON 数据仅调用一次
function JsonDecode(var Json: RawUtf8; const aName: RawUtf8 = 'result';
  WasString: PBoolean = nil;
  HandleValuesAsObjectOrArray: boolean = false): RawUtf8; overload;

/// retrieve a pointer to JSON string field content, without unescaping it
// - returns either ':' for name field, or } , for value field
// - returns nil on JSON content error
// - this function won't touch the JSON buffer, so you can call it before
// using in-place escape process via JsonDecode() or GetJsonField()
/// 检索指向 JSON 字符串字段内容的指针，而不对其进行转义
// - 对于名称字段返回 ':'，对于值字段返回 }
// - JSON 内容错误时返回 nil
// - 此函数不会接触 JSON 缓冲区，因此您可以在通过 JsonDecode() 或 GetJsonField() 使用就地转义过程之前调用它
function JsonRetrieveStringField(P: PUtf8Char; out Field: PUtf8Char;
  out FieldLen: integer; ExpectNameField: boolean): PUtf8Char;
  {$ifdef HASINLINE}inline;{$endif}

/// retrieve a class Rtti, as saved by ObjectToJson(...,[...,woStoreClassName,...]);
// - JSON input should be either 'null', either '{"ClassName":"TMyClass",...}'
// - calls IdemPropName/JsonRetrieveStringField so input buffer won't be
// modified, but caller should ignore this "ClassName" property later on
// - the corresponding class shall have been previously registered by
// Rtti.RegisterClass(), in order to retrieve the class type from it name -
// or, at least, by the RTL Classes.RegisterClass() function, if AndGlobalFindClass
// parameter is left to default true so that RTL Classes.FindClass() is called
/// 检索由  ObjectToJson(...,[...,woStoreClassName,...]) 保存的类 Rtti；
// - JSON 输入应该是 'null' 或 '{"ClassName":"TMyClass",...}'
// - 调用 IdemPropName/JsonRetrieveStringField 因此输入缓冲区不会被修改，但调用者稍后应忽略此“ClassName”属性
// - 相应的类应事先由 Rtti.RegisterClass() 注册，以便从其名称中检索类类型 - 或者至少由 RTL Classes.RegisterClass() 函数注册，如果 AndGlobalFindClass 参数保留为 默认 true 以便调用 RTL Classes.FindClass()
function JsonRetrieveObjectRttiCustom(var Json: PUtf8Char;
  AndGlobalFindClass: boolean): TRttiCustom;

/// encode a JSON object UTF-8 buffer into URI parameters
// - you can specify property names to ignore during the object decoding
// - you can omit the leading query delimiter ('?') by setting IncludeQueryDelimiter=false
// - warning: the ParametersJson input buffer will be modified in-place
/// 将 JSON 对象 UTF-8 缓冲区编码为 URI 参数
// - 您可以指定在对象解码期间要忽略的属性名称
// - 您可以通过设置 IncludeQueryDelimiter=false 来省略前导查询分隔符 ('?')
// - 警告：ParametersJson 输入缓冲区将就地修改
function UrlEncodeJsonObject(const UriName: RawUtf8; ParametersJson: PUtf8Char;
  const PropNamesToIgnore: array of RawUtf8;
  IncludeQueryDelimiter: boolean = true): RawUtf8; overload;

/// encode a JSON object UTF-8 buffer into URI parameters
// - you can specify property names to ignore during the object decoding
// - you can omit the leading query delimiter ('?') by setting IncludeQueryDelimiter=false
// - overloaded function which will make a copy of the input JSON before parsing
/// 将 JSON 对象 UTF-8 缓冲区编码为 URI 参数
// - 您可以指定在对象解码期间要忽略的属性名称
// - 您可以通过设置 IncludeQueryDelimiter=false 来省略前导查询分隔符 ('?')
// - 重载函数，它将在解析之前复制输入 JSON
function UrlEncodeJsonObject(const UriName, ParametersJson: RawUtf8;
  const PropNamesToIgnore: array of RawUtf8;
  IncludeQueryDelimiter: boolean = true): RawUtf8; overload;

/// wrapper to serialize a T*ObjArray dynamic array as JSON
// - for proper serialization on Delphi 7-2009, use Rtti.RegisterObjArray()
/// 将 T*ObjArray 动态数组序列化为 JSON 的包装器
// - 为了在 Delphi 7-2009 上正确序列化，请使用 Rtti.RegisterObjArray()
function ObjArrayToJson(const aObjArray;
  aOptions: TTextWriterWriteObjectOptions = [woDontStoreDefault]): RawUtf8;

/// encode the supplied data as an UTF-8 valid JSON object content
// - data must be supplied two by two, as Name,Value pairs, e.g.
// ! JsonEncode(['name','John','year',1972]) = '{"name":"John","year":1972}'
// - or you can specify nested arrays or objects with '['..']' or '{'..'}':
// ! J := JsonEncode(['doc','{','name','John','abc','[','a','b','c',']','}','id',123]);
// ! assert(J='{"doc":{"name":"John","abc":["a","b","c"]},"id":123}');
// - note that, due to a Delphi compiler limitation, cardinal values should be
// type-casted to Int64() (otherwise the integer mapped value will be converted)
// - you can pass nil as parameter for a null JSON value
/// 将提供的数据编码为 UTF-8 有效的 JSON 对象内容
// - 数据必须以名称、值对的形式两两提供，例如
// ! JsonEncode(['name','John','year',1972]) = '{"name":"John","year":1972}'
// - 或者您可以使用 '['..']' 或 '{'..'}' 指定嵌套数组或对象：
// ! J := JsonEncode(['doc','{','name','John','abc','[','a','b','c',']','}','id',123]);
// ! assert(J='{"doc":{"name":"John","abc":["a","b","c"]},"id":123}');
// - 请注意，由于 Delphi 编译器的限制，基数值应类型转换为 Int64() （否则整数映射值将被转换）
// - 您可以将 nil 作为 null JSON 值的参数传递
function JsonEncode(const NameValuePairs: array of const): RawUtf8; overload;

/// encode the supplied (extended) JSON content, with parameters,
// as an UTF-8 valid JSON object content
// - in addition to the JSON RFC specification strict mode, this method will
// handle some BSON-like extensions, e.g. unquoted field names:
// ! aJson := JsonEncode('{id:?,%:{name:?,birthyear:?}}',['doc'],[10,'John',1982]);
// - you can use nested _Obj() / _Arr() instances
// ! aJson := JsonEncode('{%:{$in:[?,?]}}',['type'],['food','snack']);
// ! aJson := JsonEncode('{type:{$in:?}}',[],[_Arr(['food','snack'])]);
// ! // will both return
// ! '{"type":{"$in":["food","snack"]}}')
// - if the mormot.db.nosql.bson unit is used in the application, the MongoDB
// Shell syntax will also be recognized to create TBsonVariant, like
// ! new Date()   ObjectId()   MinKey   MaxKey  /<jRegex>/<jOptions>
// see @http://docs.mongodb.org/manual/reference/mongodb-extended-json
// !  aJson := JsonEncode('{name:?,field:/%/i}',['acme.*corp'],['John']))
// ! // will return
// ! '{"name":"John","field":{"$regex":"acme.*corp","$options":"i"}}'
// - will call internally _JsonFastFmt() to create a temporary TDocVariant with
// all its features - so is slightly slower than other JsonEncode* functions
/// 使用参数对提供的（扩展）JSON 内容进行编码，
// 作为UTF-8有效的JSON对象内容
// - 除了 JSON RFC 规范严格模式之外，此方法还将处理一些类似 BSON 的扩展，例如 不带引号的字段名称：
// ! aJson := JsonEncode('{id:?,%:{name:?,birthyear:?}}',['doc'],[10,'John',1982]);
// - 您可以使用嵌套的 _Obj() / _Arr() 实例
// ! aJson := JsonEncode('{%:{$in:[?,?]}}',['type'],['food','snack']);
// ! aJson := JsonEncode('{type:{$in:?}}',[],[_Arr(['food','snack'])]);
// ! // will both return
// ! '{"type":{"$in":["food","snack"]}}')
// - 如果应用程序中使用了 mormot.db.nosql.bson 单元，则 MongoDB Shell 语法也将被识别以创建 TBsonVariant，例如
// ! new Date()   ObjectId()   MinKey   MaxKey  /<jRegex>/<jOptions>
// 请参阅@http://docs.mongodb.org/manual/reference/mongodb-extended-json
// !  aJson := JsonEncode('{name:?,field:/%/i}',['acme.*corp'],['John']))
// ! // will return
// ! '{"name":"John","field":{"$regex":"acme.*corp","$options":"i"}}'
// - 将在内部调用 _JsonFastFmt() 创建一个具有其所有功能的临时 TDocVariant - 因此比其他 JsonEncode* 函数稍慢
function JsonEncode(const Format: RawUtf8;
  const Args, Params: array of const): RawUtf8; overload;

/// encode the supplied RawUtf8 array data as an UTF-8 valid JSON array content
/// 将提供的 RawUtf8 数组数据编码为 UTF-8 有效 JSON 数组内容
function JsonEncodeArrayUtf8(
  const Values: array of RawUtf8): RawUtf8; overload;

/// encode the supplied integer array data as a valid JSON array
/// 将提供的整数数组数据编码为有效的 JSON 数组
function JsonEncodeArrayInteger(
  const Values: array of integer): RawUtf8; overload;

/// encode the supplied floating-point array data as a valid JSON array
/// 将提供的浮点数组数据编码为有效的 JSON 数组
function JsonEncodeArrayDouble(
  const Values: array of double): RawUtf8; overload;

/// encode the supplied array data as a valid JSON array content
// - if WithoutBraces is TRUE, no [ ] will be generated
// - note that, due to a Delphi compiler limitation, cardinal values should be
// type-casted to Int64() (otherwise the integer mapped value will be converted)
/// 将提供的数组数据编码为有效的 JSON 数组内容
// - 如果 WithoutBraces 为 TRUE，则不会生成 [ ]
// - 请注意，由于 Delphi 编译器的限制，基数值应类型转换为 Int64() （否则整数映射值将被转换）
function JsonEncodeArrayOfConst(const Values: array of const;
  WithoutBraces: boolean = false): RawUtf8; overload;

/// encode the supplied array data as a valid JSON array content
// - if WithoutBraces is TRUE, no [ ] will be generated
// - note that, due to a Delphi compiler limitation, cardinal values should be
// type-casted to Int64() (otherwise the integer mapped value will be converted)
/// 将提供的数组数据编码为有效的 JSON 数组内容
// - 如果 WithoutBraces 为 TRUE，则不会生成 [ ]
// - 请注意，由于 Delphi 编译器的限制，基数值应类型转换为 Int64() （否则整数映射值将被转换）
procedure JsonEncodeArrayOfConst(const Values: array of const;
  WithoutBraces: boolean; var result: RawUtf8); overload;

/// encode as JSON {"name":value} object, from a potential SQL quoted value
// - will unquote the SQLValue using TTextWriter.AddQuotedStringAsJson()
/// 从潜在的 SQL 引用值编码为 JSON {"name":value} 对象
// - 将使用 TTextWriter.AddQuotedStringAsJson() 取消对 SQLValue 的引用
procedure JsonEncodeNameSQLValue(const Name, SQLValue: RawUtf8;
  var result: RawUtf8);

/// formats and indents a JSON array or document to the specified layout
// - just a wrapper around TTextWriter.AddJsonReformat() method
// - WARNING: the JSON buffer is decoded in-place, so P^ WILL BE modified
/// 将 JSON 数组或文档格式化并缩进到指定的布局
// - 只是 TTextWriter.AddJsonReformat() 方法的包装
// - 警告：JSON 缓冲区已就地解码，因此 P^ 将被修改
procedure JsonBufferReformat(P: PUtf8Char; out result: RawUtf8;
  Format: TTextWriterJsonFormat = jsonHumanReadable);

/// formats and indents a JSON array or document to the specified layout
// - just a wrapper around TTextWriter.AddJsonReformat, making a private
// of the supplied JSON buffer (so that JSON content  would stay untouched)
/// 将 JSON 数组或文档格式化并缩进到指定的布局
// - 只是 TTextWriter.AddJsonReformat 的包装，将提供的 JSON 缓冲区设为私有（以便 JSON 内容保持不变）
function JsonReformat(const Json: RawUtf8;
  Format: TTextWriterJsonFormat = jsonHumanReadable): RawUtf8;

/// formats and indents a JSON array or document as a file
// - just a wrapper around TTextWriter.AddJsonReformat() method
// - WARNING: the JSON buffer is decoded in-place, so P^ WILL BE modified
/// 将 JSON 数组或文档格式化并缩进为文件
// - 只是 TTextWriter.AddJsonReformat() 方法的包装
// - 警告：JSON 缓冲区已就地解码，因此 P^ 将被修改
function JsonBufferReformatToFile(P: PUtf8Char; const Dest: TFileName;
  Format: TTextWriterJsonFormat = jsonHumanReadable): boolean;

/// formats and indents a JSON array or document as a file
// - just a wrapper around TTextWriter.AddJsonReformat, making a private
// of the supplied JSON buffer (so that JSON content  would stay untouched)
/// 将 JSON 数组或文档格式化并缩进为文件
// - 只是 TTextWriter.AddJsonReformat 的包装，将提供的 JSON 缓冲区设为私有（以便 JSON 内容保持不变）
function JsonReformatToFile(const Json: RawUtf8; const Dest: TFileName;
  Format: TTextWriterJsonFormat = jsonHumanReadable): boolean;


/// convert UTF-8 content into a JSON string
// - with proper escaping of the content, and surounding " characters
/// 将UTF-8内容转换为JSON字符串
// - 正确转义内容，并围绕“字符
procedure QuotedStrJson(const aText: RawUtf8; var result: RawUtf8;
  const aPrefix: RawUtf8 = ''; const aSuffix: RawUtf8 = ''); overload;
  {$ifdef HASINLINE}inline;{$endif}

/// convert UTF-8 buffer into a JSON string
// - with proper escaping of the content, and surounding " characters
/// 将UTF-8缓冲区转换为JSON字符串
// - 正确转义内容，并围绕“字符
procedure QuotedStrJson(P: PUtf8Char; PLen: PtrInt; var result: RawUtf8;
  const aPrefix: RawUtf8 = ''; const aSuffix: RawUtf8 = ''); overload;

/// convert UTF-8 content into a JSON string
// - with proper escaping of the content, and surounding " characters
/// 将UTF-8内容转换为JSON字符串
// - 正确转义内容，并围绕“字符
function QuotedStrJson(const aText: RawUtf8): RawUtf8; overload;
  {$ifdef HASINLINE}inline;{$endif}

/// fast Format() function replacement, handling % and ? parameters
// - will include Args[] for every % in Format
// - will inline Params[] for every ? in Format, handling special "inlined"
// parameters, as exected by our ORM or DB units, i.e. :(1234): for numerical
// values, and :('quoted '' string'): for textual values
// - if optional JsonFormat parameter is TRUE, ? parameters will be written
// as JSON escaped strings, without :(...): tokens, e.g. "quoted \" string"
// - resulting string has no length limit and uses fast concatenation
// - note that, due to a Delphi compiler limitation, cardinal values should be
// type-casted to Int64() (otherwise the integer mapped value will be converted)
// - any supplied TObject instance will be written as their class name
/// 快速 Format() 函数替换，处理 % 和 ? 参数
// - 将为 Format 中的每个 % 包含 Args[]
// - 将为每个 ? 内联 Params[] 在 Format 中，处理特殊的“内联”参数，由我们的 ORM 或 DB 单元执行，即 :(1234)：用于数值，和 :('quoted '' string'): 用于文本值
// - 如果可选 JsonFormat 参数为 TRUE，? 参数将被写入 JSON 转义字符串，不带 :(...): 标记，例如 “引用\”字符串”
// - 生成的字符串没有长度限制并使用快速连接
// - 请注意，由于 Delphi 编译器的限制，基数值应类型转换为 Int64() （否则整数映射值将被转换）
// - 任何提供的 TObject 实例将被写为其类名
function FormatUtf8(const Format: RawUtf8;
  const Args, Params: array of const;
  JsonFormat: boolean = false): RawUtf8; overload;


{ ********** TTextWriter class with proper JSON escaping and WriteObject() support }
{ ********** TTextWriter 类，具有正确的 JSON 转义和 WriteObject() 支持 }
type
  /// JSON-capable TBaseWriter inherited class
  // - in addition to TBaseWriter, will handle JSON serialization of any
  // kind of value, including classes
  /// 支持JSON的TBaseWriter继承类
  // - 除了 TBaseWriter 之外，还将处理任何类型值的 JSON 序列化，包括类
  TTextWriter = class(TBaseWriter)
  protected
    // used by AddCRAndIndent for enums, sets and T*ObjArray comment of values
    // 由 AddCRAndIndent 用于枚举、集合和 T*ObjArray 值注释
    fBlockComment: RawUtf8;
    // used by WriteObjectAsString/AddDynArrayJsonAsString methods
    // 由 WriteObjectAsString/AddDynArrayJsonAsString 方法使用
    fInternalJsonWriter: TTextWriter;
    procedure InternalAddFixedAnsi(Source: PAnsiChar; SourceChars: cardinal;
      AnsiToWide: PWordArray; Escape: TTextWriterKind);
    // called after TRttiCustomProp.GetValueDirect/GetValueGetter
    // 在 TRttiCustomProp.GetValueDirect/GetValueGetter 之后调用
    procedure AddRttiVarData(const Value: TRttiVarData;
      WriteOptions: TTextWriterWriteObjectOptions);
  public
    /// release all internal structures
    /// 释放所有内部结构
    destructor Destroy; override;
    /// gives access to an internal temporary TTextWriter
    // - may be used to escape some JSON espaced value (i.e. escape it twice),
    // in conjunction with AddJsonEscape(Source: TTextWriter)
    /// 提供对内部临时 TTextWriter 的访问
    // - 可以与 AddJsonEscape(Source: TTextWriter) 结合使用来转义一些 JSON 空格值（即转义两次）
    function InternalJsonWriter: TTextWriter;
    /// append '[' or '{' with proper indentation
    /// 附加带有适当缩进的“[”或“{”
    procedure BlockBegin(Starter: AnsiChar; Options: TTextWriterWriteObjectOptions);
    /// append ',' with proper indentation
    // - warning: this will break CancelLastComma, since CRLF+tabs are added
    /// 附加 ',' 并适当缩进
    // - 警告：这将破坏 CancelLastComma，因为添加了 CRLF+制表符    
    procedure BlockAfterItem(Options: TTextWriterWriteObjectOptions);
      {$ifdef HASINLINE}inline;{$endif}
    /// append ']' or '}' with proper indentation
    /// 添加带有适当缩进的 ']' 或 '}'
    procedure BlockEnd(Stopper: AnsiChar; Options: TTextWriterWriteObjectOptions);
    /// used internally by WriteObject() when serializing a published property
    // - will call AddCRAndIndent then append "PropName":
    /// 序列化已发布属性时由 WriteObject() 在内部使用
    // - 将调用 AddCRAndIndent 然后附加“PropName”：
    procedure WriteObjectPropName(PropName: PUtf8Char; PropNameLen: PtrInt;
      Options: TTextWriterWriteObjectOptions);
    /// used internally by WriteObject() when serializing a published property
    // - will call AddCRAndIndent then append "PropName":
    /// 序列化已发布属性时由 WriteObject() 在内部使用
    // - 将调用 AddCRAndIndent 然后附加“PropName”：
    procedure WriteObjectPropNameShort(const PropName: shortstring;
      Options: TTextWriterWriteObjectOptions);
      {$ifdef HASINLINE}inline;{$endif}
    /// same as WriteObject(), but will double all internal " and bound with "
    // - this implementation will avoid most memory allocations
    /// 与 WriteObject() 相同，但会将所有内部 " 加倍并与 " 绑定
    // - 此实现将避免大多数内存分配    
    procedure WriteObjectAsString(Value: TObject;
      Options: TTextWriterWriteObjectOptions = [woDontStoreDefault]);
    /// same as AddDynArrayJson(), but will double all internal " and bound with "
    // - this implementation will avoid most memory allocations
    /// 与 AddDynArrayJson() 相同，但会将所有内部 " 加倍并与 " 绑定
    // - 此实现将避免大多数内存分配
    procedure AddDynArrayJsonAsString(aTypeInfo: PRttiInfo; var aValue;
      WriteOptions: TTextWriterWriteObjectOptions = []);
    /// append a JSON field name, followed by an escaped UTF-8 JSON String and
    // a comma (',')
    /// 附加 JSON 字段名称，后跟转义的 UTF-8 JSON 字符串和逗号 (',')
    procedure AddPropJsonString(const PropName: shortstring; const Text: RawUtf8);
    /// append a JSON field name, followed by a number value and a comma (',')
    /// 附加 JSON 字段名称，后跟数字值和逗号 (',')
    procedure AddPropJSONInt64(const PropName: shortstring; Value: Int64);
    /// append CR+LF (#13#10) chars and #9 indentation
    // - will also flush any fBlockComment
    /// 附加 CR+LF (#13#10) 字符和 #9 缩进
    // - 还将刷新任何 fBlockComment
    procedure AddCRAndIndent; override;
    /// write some #0 ended UTF-8 text, according to the specified format
    // - if Escape is a constant, consider calling directly AddNoJsonEscape,
    // AddJsonEscape or AddOnSameLine methods
    /// 根据指定的格式写入一些#0结尾的UTF-8文本
    // - 如果 Escape 是常量，请考虑直接调用 AddNoJsonEscape、AddJsonEscape 或 AddOnSameLine 方法
    procedure Add(P: PUtf8Char; Escape: TTextWriterKind); override;
    /// write some #0 ended UTF-8 text, according to the specified format
    // - if Escape is a constant, consider calling directly AddNoJsonEscape,
    // AddJsonEscape or AddOnSameLine methods
    /// 根据指定的格式写入一些#0结尾的UTF-8文本
    // - 如果 Escape 是常量，请考虑直接调用 AddNoJsonEscape、AddJsonEscape 或 AddOnSameLine 方法
    procedure Add(P: PUtf8Char; Len: PtrInt; Escape: TTextWriterKind); override;
    /// write some #0 ended Unicode text as UTF-8, according to the specified format
    // - if Escape is a constant, consider calling directly AddNoJsonEscapeW,
    // AddJsonEscapeW or AddOnSameLineW methods
    /// 根据指定的格式，将一些#0结尾的Unicode文本写入UTF-8
    // - 如果 Escape 是常量，请考虑直接调用 AddNoJsonEscapeW、AddJsonEscapeW 或 AddOnSameLineW 方法
    procedure AddW(P: PWord; Len: PtrInt; Escape: TTextWriterKind);
      {$ifdef HASINLINE}inline;{$endif}
    /// append some UTF-8 encoded chars to the buffer, from the main AnsiString type
    // - use the current system code page for AnsiString parameter
    /// 将一些 UTF-8 编码的字符从主 AnsiString 类型附加到缓冲区
    // - 使用当前系统代码页作为 AnsiString 参数
    procedure AddAnsiString(const s: AnsiString; Escape: TTextWriterKind); overload;
    /// append some UTF-8 encoded chars to the buffer, from any AnsiString value
    // - if CodePage is left to its default value of -1, it will assume
    // CurrentAnsiConvert.CodePage prior to Delphi 2009, but newer UNICODE
    // versions of Delphi will retrieve the code page from string
    // - if CodePage is defined to a >= 0 value, the encoding will take place
    /// 将任何 AnsiString 值中的一些 UTF-8 编码字符附加到缓冲区
    // - 如果 CodePage 保留默认值 -1，它将采用 Delphi 2009 之前的 CurrentAnsiConvert.CodePage，但较新的 UNICODE 版本的 Delphi 将从字符串中检索代码页
    // - 如果 CodePage 定义为 >= 0 值，则将进行编码    
    procedure AddAnyAnsiString(const s: RawByteString; Escape: TTextWriterKind;
      CodePage: integer = -1);
    /// append some UTF-8 encoded chars to the buffer, from any Ansi buffer
    // - the codepage should be specified, e.g. CP_UTF8, CP_RAWBYTESTRING,
    // CODEPAGE_US, or any version supported by the Operating System
    // - if codepage is 0, the current CurrentAnsiConvert.CodePage would be used
    // - will use TSynAnsiConvert to perform the conversion to UTF-8
    /// 将一些 UTF-8 编码的字符从任何 Ansi 缓冲区附加到缓冲区
    // - 应指定代码页，例如 CP_UTF8、CP_RAWBYTESTRING、CODEPAGE_US 或操作系统支持的任何版本
    // - 如果代码页为 0，则将使用当前的 CurrentAnsiConvert.CodePage
    // - 将使用 TSynAnsiConvert 执行到 UTF-8 的转换
    procedure AddAnyAnsiBuffer(P: PAnsiChar; Len: PtrInt;
      Escape: TTextWriterKind; CodePage: integer);
    /// write some data Base64 encoded
    // - if withMagic is TRUE, will write as '"\uFFF0base64encodedbinary"'
    /// 写入一些Base64编码的数据
    // - 如果 withMagic 为 TRUE，将写为 '"\uFFF0base64encodedbinary"'
    procedure WrBase64(P: PAnsiChar; Len: PtrUInt; withMagic: boolean); override;
    /// write some binary-saved data with Base64 encoding
    // - if withMagic is TRUE, will write as '"\uFFF0base64encodedbinary"'
    // - is a wrapper around BinarySave() and WrBase64()
    /// 用Base64编码写入一些二进制保存的数据
    // - 如果 withMagic 为 TRUE，将写为 '"\uFFF0base64encodedbinary"'
    // - 是 BinarySave() 和 WrBase64() 的包装
    procedure BinarySaveBase64(Data: pointer; Info: PRttiInfo;
      Kinds: TRttiKinds; withMagic: boolean; withCrc: boolean = false);
    /// append some values at once
    // - text values (e.g. RawUtf8) will be escaped as JSON
    /// 一次追加一些值
    // - 文本值（例如 RawUtf8）将转义为 JSON
    procedure Add(const Values: array of const); overload;
    /// append an array of integers as CSV
    /// 将整数数组附加为 CSV
    procedure AddCsvInteger(const Integers: array of integer); overload;
    /// append an array of doubles as CSV
    /// 将双精度数组附加为 CSV
    procedure AddCsvDouble(const Doubles: array of double); overload;
    /// append an array of RawUtf8 as CSV of JSON strings
    /// 将 RawUtf8 数组附加为 JSON 字符串的 CSV
    procedure AddCsvUtf8(const Values: array of RawUtf8); overload;
    /// append an array of const as CSV of JSON values
    /// 将 const 数组附加为 JSON 值的 CSV
    procedure AddCsvConst(const Values: array of const);
    /// append a quoted string as JSON, with in-place decoding
    // - if QuotedString does not start with ' or ", it will written directly
    // (i.e. expects to be a number, or null/true/false constants)
    // - as used e.g. by TJsonObjectDecoder.EncodeAsJson method and
    // JsonEncodeNameSQLValue() function
    /// 将带引号的字符串附加为 JSON，并进行就地解码
    // - 如果 QuotedString 不以 ' 或 " 开头，它将直接写入（即期望为数字或 null/true/false 常量）
    // - 如所使用的，例如 通过 TJsonObjectDecoder.EncodeAsJson 方法和 JsonEncodeNameSQLValue() 函数    
    procedure AddQuotedStringAsJson(const QuotedString: RawUtf8);
    /// append a TTimeLog value, expanded as Iso-8601 encoded text
    /// 附加一个 TTimeLog 值，扩展为 Iso-8601 编码文本
    procedure AddTimeLog(Value: PInt64; QuoteChar: AnsiChar = #0);
    /// append a TUnixTime value, expanded as Iso-8601 encoded text
    /// 附加一个 TUnixTime 值，扩展为 Iso-8601 编码文本
    procedure AddUnixTime(Value: PInt64; QuoteChar: AnsiChar = #0);
    /// append a TUnixMSTime value, expanded as Iso-8601 encoded text
    /// 附加一个 TUnixMSTime 值，扩展为 Iso-8601 编码文本
    procedure AddUnixMSTime(Value: PInt64; WithMS: boolean = false;
      QuoteChar: AnsiChar = #0);
    /// append a TDateTime value, expanded as Iso-8601 encoded text
    // - use 'YYYY-MM-DDThh:mm:ss' format (with FirstChar='T')
    // - if WithMS is TRUE, will append '.sss' for milliseconds resolution
    // - if QuoteChar is not #0, it will be written before and after the date
    /// 附加一个 TDateTime 值，扩展为 Iso-8601 编码文本
    // - 使用 'YYYY-MM-DDThh:mm:ss' 格式（FirstChar='T'）
    // - 如果 WithMS 为 TRUE，将附加“.sss”以获得毫秒分辨率
    // - 如果 QuoteChar 不是 #0，则会在日期之前和之后写入
    procedure AddDateTime(Value: PDateTime; FirstChar: AnsiChar = 'T';
      QuoteChar: AnsiChar = #0; WithMS: boolean = false;
      AlwaysDateAndTime: boolean = false); overload;
    /// append a TDateTime value, expanded as Iso-8601 encoded text
    // - use 'YYYY-MM-DDThh:mm:ss' format
    // - append nothing if Value=0
    // - if WithMS is TRUE, will append '.sss' for milliseconds resolution
    /// 附加一个 TDateTime 值，扩展为 Iso-8601 编码文本
    // - 使用 'YYYY-MM-DDThh:mm:ss' 格式
    // - 如果 Value=0，则不追加任何内容
    // - 如果 WithMS 为 TRUE，将附加“.sss”以获得毫秒分辨率
    procedure AddDateTime(const Value: TDateTime; WithMS: boolean = false); overload;
    /// append a TDateTime value, expanded as Iso-8601 text with milliseconds
    // and Time Zone designator
    // - i.e. 'YYYY-MM-DDThh:mm:ss.sssZ' format
    // - TZD is the ending time zone designator ('', 'Z' or '+hh:mm' or '-hh:mm')
    /// 附加一个 TDateTime 值，扩展为带有毫秒和时区指示符的 Iso-8601 文本
    // - 即 'YYYY-MM-DDThh:mm:ss.sssZ' 格式
    // - TZD 是结束时区指示符 ('', 'Z' or '+hh:mm' or '-hh:mm')
    procedure AddDateTimeMS(const Value: TDateTime; Expanded: boolean = true;
      FirstTimeChar: AnsiChar = 'T'; const TZD: RawUtf8 = 'Z');
    /// append the current UTC date and time, in our log-friendly format
    // - e.g. append '20110325 19241502' - with no trailing space nor tab
    // - you may set LocalTime=TRUE to write the local date and time instead
    // - this method is very fast, and avoid most calculation or API calls
    /// 以我们的日志友好格式附加当前 UTC 日期和时间
    // - 例如 追加 '20110325 19241502' - 没有尾随空格或制表符
    // - 您可以设置 LocalTime=TRUE 来写入本地日期和时间
    // - 这个方法非常快，并且避免了大多数计算或 API 调用
    procedure AddCurrentLogTime(LocalTime: boolean);
    /// append the current UTC date and time, in our log-friendly format
    // - e.g. append '19/Feb/2019:06:18:55 ' - including a trailing space
    // - you may set LocalTime=TRUE to write the local date and time instead
    // - this method is very fast, and avoid most calculation or API calls
    /// 以我们的日志友好格式附加当前 UTC 日期和时间
    // - 例如 追加 '19/Feb/2019:06:18:55 ' - 包括尾随空格
    // - 您可以设置 LocalTime=TRUE 来写入本地日期和时间
    // - 这个方法非常快，并且避免了大多数计算或 API 调用
    procedure AddCurrentNCSALogTime(LocalTime: boolean);

    /// append strings or integers with a specified format
    // - this overriden version will properly handle JSON escape
    // - % = #37 marks a string, integer, floating-point, or class parameter
    // to be appended as text (e.g. class name)
    // - note that due to a limitation of the "array of const" format, cardinal
    // values should be type-casted to Int64() - otherwise the integer mapped
    // value will be transmitted, therefore wrongly
    /// 附加指定格式的字符串或整数
    // - 这个重写版本将正确处理 JSON 转义
    // - % = #37 标记要作为文本附加的字符串、整数、浮点或类参数（例如类名）
    // - 请注意，由于“常量数组”格式的限制，基数值应类型转换为 Int64() - 否则将传输整数映射值，因此会出现错误    
    procedure Add(const Format: RawUtf8; const Values: array of const;
      Escape: TTextWriterKind = twNone;
      WriteObjectOptions: TTextWriterWriteObjectOptions = [woFullExpand]); override;
    /// append a variant content as number or string
    // - this overriden version will properly handle JSON escape
    // - properly handle Value as a TRttiVarData from TRttiProp.GetValue
    /// 以数字或字符串形式附加变体内容
    // - 这个重写版本将正确处理 JSON 转义
    // - 正确处理 TRttiProp.GetValue 中的 Value 作为 TRttiVarData    
    procedure AddVariant(const Value: variant; Escape: TTextWriterKind = twJsonEscape;
      WriteOptions: TTextWriterWriteObjectOptions = []); override;
    /// append complex types as JSON content using raw TypeInfo()
    // - handle rkClass as WriteObject, rkEnumeration/rkSet with proper options,
    // rkRecord, rkDynArray or rkVariant using proper JSON serialization
    // - other types will append 'null'
    /// 使用原始 TypeInfo() 将复杂类型附加为 JSON 内容
    // - 使用适当的选项将 rkClass 处理为 WriteObject、rkEnumeration/rkSet，
    // 使用正确的 JSON 序列化的 rkRecord、rkDynArray 或 rkVariant
    // - 其他类型将附加“null”    
    procedure AddTypedJson(Value, TypeInfo: pointer;
      WriteOptions: TTextWriterWriteObjectOptions = []); override;
    /// serialize as JSON the given object
    /// 将给定对象序列化为 JSON
    procedure WriteObject(Value: TObject;
      WriteOptions: TTextWriterWriteObjectOptions = [woDontStoreDefault]); override;
    /// append complex types as JSON content using TRttiCustom
    // - called e.g. by TTextWriter.AddVariant() for varAny / TRttiVarData
    /// 使用 TRttiCustom 将复杂类型附加为 JSON 内容
    // - 称为例如 通过 TTextWriter.AddVariant() 为 varAny / TRttiVarData
    procedure AddRttiCustomJson(Value: pointer; RttiCustom: TObject;
      WriteOptions: TTextWriterWriteObjectOptions);
    /// append a JSON value, array or document, in a specified format
    // - this overriden version will properly handle JSON escape
    /// 以指定格式附加 JSON 值、数组或文档
    // - 这个重写版本将正确处理 JSON 转义
    function AddJsonReformat(Json: PUtf8Char; Format: TTextWriterJsonFormat;
      EndOfObject: PUtf8Char): PUtf8Char; override;
    /// append a JSON value, array or document as simple XML content
    // - you can use JsonBufferToXML() and JsonToXML() functions as wrappers
    // - this method is called recursively to handle all kind of JSON values
    // - WARNING: the JSON buffer is decoded in-place, so will be changed
    // - returns the end of the current JSON converted level, or nil if the
    // supplied content was not correct JSON
    /// 将 JSON 值、数组或文档附加为简单的 XML 内容
    // - 您可以使用 JsonBufferToXML() 和 JsonToXML() 函数作为包装器
    // - 递归调用此方法来处理所有类型的 JSON 值
    // - 警告：JSON 缓冲区已就地解码，因此将被更改
    // - 返回当前 JSON 转换级别的结尾，如果提供的内容不是正确的 JSON，则返回 nil
    function AddJsonToXML(Json: PUtf8Char; ArrayName: PUtf8Char = nil;
      EndOfObject: PUtf8Char = nil): PUtf8Char;

    /// append a record content as UTF-8 encoded JSON or custom serialization
    // - default serialization will use Base64 encoded binary stream, or
    // a custom serialization, in case of a previous registration via
    // RegisterCustomJsonSerializer() class method - from a dynamic array
    // handling this kind of records, or directly from TypeInfo() of the record
    // - by default, custom serializers defined via RegisterCustomJsonSerializer()
    // would write enumerates and sets as integer numbers, unless
    // twoEnumSetsAsTextInRecord or twoEnumSetsAsBooleanInRecord is set in
    // the instance CustomOptions
    // - returns the element size
    /// 将记录内容追加为UTF-8编码的JSON或自定义序列化
    // - 默认序列化将使用 Base64 编码的二进制流，或自定义序列化（如果之前通过 RegisterCustomJsonSerializer() 类方法进行注册） - 来自处理此类记录的动态数组，或直接来自记录的 TypeInfo()
    // - 默认情况下，通过 RegisterCustomJsonSerializer() 定义的自定义序列化程序会将枚举和集合写入整数，除非在实例 CustomOptions 中设置了twoEnumSetsAsTextInRecord 或twoEnumSetsAsBooleanInRecord
    // - 返回元素大小    
    function AddRecordJson(Value: pointer; RecordInfo: PRttiInfo;
      WriteOptions: TTextWriterWriteObjectOptions = []): PtrInt;
    /// append a void record content as UTF-8 encoded JSON or custom serialization
    // - this method will first create a void record (i.e. filled with #0 bytes)
    // then save its content with default or custom serialization
    /// 附加一个void记录内容作为UTF-8编码的JSON或自定义序列化
    // - 此方法将首先创建一个空记录（即填充#0字节），然后使用默认或自定义序列化保存其内容
    procedure AddVoidRecordJson(RecordInfo: PRttiInfo;
      WriteOptions: TTextWriterWriteObjectOptions = []);
    /// append a dynamic array content as UTF-8 encoded JSON array
    // - typical content could be
    // ! '[1,2,3,4]' or '["\uFFF0base64encodedbinary"]'
    /// 将动态数组内容附加为 UTF-8 编码的 JSON 数组
    // - 典型内容可能是
    // ! '[1,2,3,4]' or '["\uFFF0base64encodedbinary"]'
    procedure AddDynArrayJson(var DynArray: TDynArray;
      WriteOptions: TTextWriterWriteObjectOptions = []); overload;
    /// append a dynamic array content as UTF-8 encoded JSON array
    // - expect a dynamic array TDynArrayHashed wrapper as incoming parameter
    /// 将动态数组内容附加为 UTF-8 编码的 JSON 数组
    // - 期望动态数组 TDynArrayHashed 包装器作为传入参数
    procedure AddDynArrayJson(var DynArray: TDynArrayHashed;
      WriteOptions: TTextWriterWriteObjectOptions = []); overload;
      {$ifdef HASINLINE}inline;{$endif}
    /// append a dynamic array content as UTF-8 encoded JSON array
    // - returns the array element size
    /// 将动态数组内容附加为 UTF-8 编码的 JSON 数组
    // - 返回数组元素大小
    function AddDynArrayJson(Value: pointer; Info: TRttiCustom;
      WriteOptions: TTextWriterWriteObjectOptions = []): PtrInt; overload;
    /// append UTF-8 content as text
    // - Text CodePage will be used (if possible) - assume RawUtf8 otherwise
    // - will properly handle JSON escape between two " double quotes
    /// 将 UTF-8 内容附加为文本
    // - 将使用文本代码页（如果可能） - 否则假设为 RawUtf8
    // - 将正确处理两个“双引号之间的 JSON 转义
    procedure AddText(const Text: RawByteString; Escape: TTextWriterKind = twJsonEscape);
    /// append UTF-16 content as text
    // - P should be a #0 terminated PWideChar buffer
    // - will properly handle JSON escape between two " double quotes
    /// 将 UTF-16 内容附加为文本
    // - P 应该是 #0 终止的 PWideChar 缓冲区
    // - 将正确处理两个“双引号之间的 JSON 转义
    procedure AddTextW(P: PWord; Escape: TTextWriterKind = twJsonEscape);
    /// append some UTF-8 encoded chars to the buffer
    // - escapes chars according to the JSON RFC
    // - if Len is 0, writing will stop at #0 (default Len = 0 is slightly faster
    // than specifying Len>0 if you are sure P is zero-ended - e.g. from RawUtf8)
    /// 将一些UTF-8编码的字符附加到缓冲区
    // - 根据 JSON RFC 转义字符
    // - 如果 Len 为 0，则写入将在 #0 处停止（如果您确定 P 是零结束的，则默认 Len = 0 比指定 Len>0 稍快 - 例如来自 RawUtf8）
    procedure AddJsonEscape(P: Pointer; Len: PtrInt = 0); overload;
    /// append some Unicode encoded chars to the buffer
    // - if Len is 0, Len is calculated from zero-ended widechar
    // - escapes chars according to the JSON RFC
    /// 将一些 Unicode 编码的字符附加到缓冲区
    // - 如果 Len 为 0，则 Len 是根据零端宽字符计算的
    // - 根据 JSON RFC 转义字符
    procedure AddJsonEscapeW(P: PWord; Len: PtrInt = 0);
    /// append some UTF-8 encoded chars to the buffer, from a generic string type
    // - faster than AddJsonEscape(pointer(StringToUtf8(string))
    // - escapes chars according to the JSON RFC
    /// 将一些 UTF-8 编码的字符从通用字符串类型附加到缓冲区
    // - 比 AddJsonEscape(pointer(StringToUtf8(string)) 更快
    // - 根据 JSON RFC 转义字符
    procedure AddJsonEscapeString(const s: string);
      {$ifdef HASINLINE}inline;{$endif}
    /// append some UTF-8 encoded chars to the buffer, from the main AnsiString type
    // - escapes chars according to the JSON RFC
    /// 将一些 UTF-8 编码的字符从主 AnsiString 类型附加到缓冲区
    // - 根据 JSON RFC 转义字符
    procedure AddJsonEscapeAnsiString(const s: AnsiString);
    /// append an open array constant value to the buffer
    // - "" will be added if necessary
    // - escapes chars according to the JSON RFC
    // - very fast (avoid most temporary storage)
    /// 将一个开放数组常量值追加到缓冲区
    // - 如果需要的话将添加“”
    // - 根据 JSON RFC 转义字符
    // - 非常快（避免大多数临时存储）
    procedure AddJsonEscape(const V: TVarRec); overload;
    /// append a UTF-8 JSON String, between double quotes and with JSON escaping
    /// 在双引号之间附加一个 UTF-8 JSON 字符串并使用 JSON 转义
    procedure AddJsonString(const Text: RawUtf8);
    /// flush a supplied TTextWriter, and write pending data as JSON escaped text
    // - may be used with InternalJsonWriter, as a faster alternative to
    // ! AddJsonEscape(Pointer(fInternalJsonWriter.Text),0);
    /// 刷新提供的 TTextWriter，并将挂起的数据写入 JSON 转义文本
    // - 可以与InternalJsonWriter一起使用，作为更快的替代方案
    // ! AddJsonEscape(Pointer(fInternalJsonWriter.Text),0);
    procedure AddJsonEscape(Source: TTextWriter); overload;
    /// flush a supplied TTextWriter, and write pending data as JSON escaped text
    // - may be used with InternalJsonWriter, as a faster alternative to
    // ! AddNoJsonEscapeUtf8(Source.Text);
    /// 刷新提供的 TTextWriter，并将挂起的数据写入 JSON 转义文本
    // - 可以与InternalJsonWriter一起使用，作为更快的替代方案
    // ! AddNoJsonEscapeUtf8(Source.Text);
    procedure AddNoJsonEscape(Source: TTextWriter); overload;
    /// append an open array constant value to the buffer
    // - "" won't be added for string values
    // - string values may be escaped, depending on the supplied parameter
    // - very fast (avoid most temporary storage)
    /// 将一个开放数组常量值追加到缓冲区
    // - 字符串值不会添加“”
    // - 字符串值可能会被转义，具体取决于提供的参数
    // - 非常快（避免大多数临时存储）
    procedure Add(const V: TVarRec; Escape: TTextWriterKind = twNone;
      WriteObjectOptions: TTextWriterWriteObjectOptions = [woFullExpand]); overload;
    /// encode the supplied data as an UTF-8 valid JSON object content
    // - data must be supplied two by two, as Name,Value pairs, e.g.
    // ! aWriter.AddJsonEscape(['name','John','year',1972]);
    // will append to the buffer:
    // ! '{"name":"John","year":1972}'
    // - or you can specify nested arrays or objects with '['..']' or '{'..'}':
    // ! aWriter.AddJsonEscape(['doc','{','name','John','ab','[','a','b']','}','id',123]);
    // will append to the buffer:
    // ! '{"doc":{"name":"John","abc":["a","b"]},"id":123}'
    // - note that, due to a Delphi compiler limitation, cardinal values should be
    // type-casted to Int64() (otherwise the integer mapped value will be converted)
    // - you can pass nil as parameter for a null JSON value
    /// 将提供的数据编码为 UTF-8 有效的 JSON 对象内容
    // - 数据必须以名称、值对的形式两两提供，例如
    // ! aWriter.AddJsonEscape(['name','John','year',1972]);
    // 将追加到缓冲区：
    // ! '{"name":"John","year":1972}'
    // - 或者您可以使用 '['..']' 或 '{'..'}' 指定嵌套数组或对象：
    // ! aWriter.AddJsonEscape(['doc','{','name','John','ab','[','a','b']','}','id',123]);
    // 将追加到缓冲区：
    // ! '{"doc":{"name":"John","abc":["a","b"]},"id":123}'
    // - 请注意，由于 Delphi 编译器的限制，基数值应类型转换为 Int64() （否则整数映射值将被转换）
    // - 您可以将 nil 作为 null JSON 值的参数传递
    procedure AddJsonEscape(
      const NameValuePairs: array of const); overload;
    /// encode the supplied (extended) JSON content, with parameters,
    // as an UTF-8 valid JSON object content
    // - in addition to the JSON RFC specification strict mode, this method will
    // handle some BSON-like extensions, e.g. unquoted field names:
    // ! aWriter.AddJson('{id:?,%:{name:?,birthyear:?}}',['doc'],[10,'John',1982]);
    // - you can use nested _Obj() / _Arr() instances
    // ! aWriter.AddJson('{%:{$in:[?,?]}}',['type'],['food','snack']);
    // ! aWriter.AddJson('{type:{$in:?}}',[],[_Arr(['food','snack'])]);
    // ! // which are the same as:
    // ! aWriter.AddShort('{"type":{"$in":["food","snack"]}}');
    // - if the mormot.db.nosql.bson unit is used in the application, the MongoDB
    // Shell syntax will also be recognized to create TBsonVariant, like
    // ! new Date()   ObjectId()   MinKey   MaxKey  /<jRegex>/<jOptions>
    // see @http://docs.mongodb.org/manual/reference/mongodb-extended-json
    // !  aWriter.AddJson('{name:?,field:/%/i}',['acme.*corp'],['John']))
    // ! // will write
    // ! '{"name":"John","field":{"$regex":"acme.*corp","$options":"i"}}'
    // - will call internally _JsonFastFmt() to create a temporary TDocVariant
    // with all its features - so is slightly slower than other AddJson* methods
    /// 使用参数将提供的（扩展）JSON 内容编码为 UTF-8 有效 JSON 对象内容
    // - 除了 JSON RFC 规范严格模式之外，此方法还将处理一些类似 BSON 的扩展，例如 不带引号的字段名称：
    // ! aWriter.AddJson('{id:?,%:{name:?,birthyear:?}}',['doc'],[10,'John',1982]);
    // - 您可以使用嵌套的 _Obj() / _Arr() 实例
    // ! aWriter.AddJson('{%:{$in:[?,?]}}',['type'],['food','snack']);
    // ! aWriter.AddJson('{type:{$in:?}}',[],[_Arr(['food','snack'])]);
    // ! // which are the same as:
    // ! aWriter.AddShort('{"type":{"$in":["food","snack"]}}');
    // - 如果应用程序中使用 mormot.db.nosql.bson 单元，则 MongoDB
    // Shell 语法也将被识别以创建 TBsonVariant，例如
    // ! new Date()   ObjectId()   MinKey   MaxKey  /<jRegex>/<jOptions>
    // 请参阅@http://docs.mongodb.org/manual/reference/mongodb-extended-json
    // !  aWriter.AddJson('{name:?,field:/%/i}',['acme.*corp'],['John']))
    // ! // will write
    // ! '{"name":"John","field":{"$regex":"acme.*corp","$options":"i"}}'
    // - 将在内部调用 _JsonFastFmt() 创建一个具有其所有功能的临时 TDocVariant - 因此比其他 AddJson* 方法稍慢    
    procedure AddJson(const Format: RawUtf8;
      const Args, Params: array of const);
    /// append two JSON arrays of keys and values as one JSON object
    // - i.e. makes the following transformation:
    // $ [key1,key2...] + [value1,value2...] -> {key1:value1,key2,value2...}
    // - this method won't allocate any memory during its process, nor
    // modify the keys and values input buffers
    // - is the reverse of the JsonObjectAsJsonArrays() function
    // - used e.g. by TSynDictionary.SaveToJson
    /// 将两个键和值的 JSON 数组附加为一个 JSON 对象
    // - 即进行以下转换：
    // $ [key1,key2...] + [value1,value2...] -> {key1:value1,key2,value2...}
    // - 此方法在其过程中不会分配任何内存，也不会修改键和值输入缓冲区
    // - 与 JsonObjectAsJsonArrays() 函数相反
    // - 例如使用 通过 TSynDictionary.SaveToJson
    procedure AddJsonArraysAsJsonObject(keys, values: PUtf8Char);
  end;


{ ************ JSON-aware TSynNameValue TSynPersistentStoreJson }
{ ************ JSON 感知 TSynNameValue TSynPersistentStoreJson }

type
  /// store one Name/Value pair, as used by TSynNameValue class
  /// 存储一个名称/值对，由 TSynNameValue 类使用
  TSynNameValueItem = record
    /// the name of the Name/Value pair
    // - this property is hashed by TSynNameValue for fast retrieval
    /// 名称/值对的名称
    // - 该属性由 TSynNameValue 进行哈希处理以便快速检索
    Name: RawUtf8;
    /// the value of the Name/Value pair
    /// 名称/值对的值
    Value: RawUtf8;
    /// any associated Pointer or numerical value
    /// 任何关联的指针或数值
    Tag: PtrInt;
  end;

  /// Name/Value pairs storage, as used by TSynNameValue class
  /// 名称/值对存储，由 TSynNameValue 类使用
  TSynNameValueItemDynArray = array of TSynNameValueItem;

  /// event handler used to convert on the fly some UTF-8 text content
  /// 用于动态转换一些 UTF-8 文本内容的事件处理程序
  TOnSynNameValueConvertRawUtf8 = function(
    const text: RawUtf8): RawUtf8 of object;

  /// callback event used by TSynNameValue
  /// TSynNameValue 使用的回调事件
  TOnSynNameValueNotify = procedure(
    const Item: TSynNameValueItem; Index: PtrInt) of object;

  /// pseudo-class used to store Name/Value RawUtf8 pairs
  // - use internally a TDynArrayHashed instance for fast retrieval
  // - is therefore faster than TRawUtf8List
  // - is defined as an object, not as a class: you can use this in any
  // class, without the need to destroy the content
  // - Delphi "object" is buggy on stack -> also defined as record with methods
  /// 用于存储名称/值 RawUtf8 对的伪类
  // - 在内部使用 TDynArrayHashed 实例进行快速检索
  // - 因此比 TRawUtf8List 更快
  // - 被定义为对象，而不是类：您可以在任何类中使用它，而不需要销毁内容
  // - Delphi“对象”在堆栈上存在错误 -> 也定义为带有方法的记录
  {$ifdef USERECORDWITHMETHODS}
  TSynNameValue = record
  private
  {$else}
  TSynNameValue = object
  protected
  {$endif USERECORDWITHMETHODS}
    fOnAdd: TOnSynNameValueNotify;
    function GetBlobData: RawByteString;
    procedure SetBlobData(const aValue: RawByteString);
    function GetStr(const aName: RawUtf8): RawUtf8;
      {$ifdef HASINLINE}inline;{$endif}
    function GetInt(const aName: RawUtf8): Int64;
      {$ifdef HASINLINE}inline;{$endif}
    function GetBool(const aName: RawUtf8): boolean;
      {$ifdef HASINLINE}inline;{$endif}
  public
    /// the internal Name/Value storage
    /// 内部名称/值存储
    List: TSynNameValueItemDynArray;
    /// the number of Name/Value pairs
    /// 名称/值对的数量
    Count: integer;
    /// low-level access to the internal storage hasher
    /// 对内部存储哈希器的低级访问
    DynArray: TDynArrayHashed;
    /// initialize the storage
    // - will also reset the internal List[] and the internal hash array
    /// 初始化存储
    // - 还将重置内部 List[] 和内部哈希数组
    procedure Init(aCaseSensitive: boolean);
    /// add an element to the array
    // - if aName already exists, its associated Value will be updated
    /// 向数组添加一个元素
    // - 如果 aName 已经存在，则其关联的 Value 将被更新
    procedure Add(const aName, aValue: RawUtf8; aTag: PtrInt = 0);
    /// reset content, then add all name=value pairs from a supplied .ini file
    // section content
    // - will first call Init(false) to initialize the internal array
    // - Section can be retrieved e.g. via FindSectionFirstLine()
    /// 重置内容，然后添加提供的 .ini 文件部分内容中的所有名称=值对
    // - 将首先调用 Init(false) 来初始化内部数组
    // - 可以检索部分，例如 通过 FindSectionFirstLine()
    procedure InitFromIniSection(Section: PUtf8Char;
      const OnTheFlyConvert: TOnSynNameValueConvertRawUtf8 = nil;
      const OnAdd: TOnSynNameValueNotify = nil);
    /// reset content, then add all name=value; CSV pairs
    // - will first call Init(false) to initialize the internal array
    // - if ItemSep=#10, then any kind of line feed (CRLF or LF) will be handled
    /// 重置内容，然后添加所有name=value; CSV 对
    // - 将首先调用 Init(false) 来初始化内部数组
    // - 如果 ItemSep=#10，则将处理任何类型的换行符（CRLF 或 LF）
    procedure InitFromCsv(Csv: PUtf8Char; NameValueSep: AnsiChar = '=';
      ItemSep: AnsiChar = #10);
    /// reset content, then add all fields from an JSON object
    // - will first call Init() to initialize the internal array
    // - then parse the incoming JSON object, storing all its field values
    // as RawUtf8, and returning TRUE if the supplied content is correct
    // - warning: the supplied JSON buffer will be decoded and modified in-place
    /// 重置内容，然后添加 JSON 对象中的所有字段
    // - 将首先调用 Init() 来初始化内部数组
    // - 然后解析传入的 JSON 对象，将其所有字段值存储为 RawUtf8，如果提供的内容正确则返回 TRUE
    // - 警告：提供的 JSON 缓冲区将被解码并就地修改
    function InitFromJson(Json: PUtf8Char; aCaseSensitive: boolean = false): boolean;
    /// reset content, then add all name, value pairs
    // - will first call Init(false) to initialize the internal array
    /// 重置内容，然后添加所有名称、值对
    // - 将首先调用 Init(false) 来初始化内部数组
    procedure InitFromNamesValues(const Names, Values: array of RawUtf8);
    /// search for a Name, return the index in List
    // - using fast O(1) hash algoritm
    /// 搜索一个Name，返回List中的索引
    // - 使用快速 O(1) 哈希算法
    function Find(const aName: RawUtf8): integer;
    /// search for the first chars of a Name, return the index in List
    // - using O(n) calls of IdemPChar() function
    // - here aUpperName should be already uppercase, as expected by IdemPChar()
    /// 搜索Name的第一个字符，返回List中的索引
    // - 使用 IdemPChar() 函数的 O(n) 次调用
    // - 这里 aUpperName 应该已经是大写的，正如 IdemPChar() 所期望的那样
    function FindStart(const aUpperName: RawUtf8): PtrInt;
    /// search for a Value, return the index in List
    // - using O(n) brute force algoritm with case-sensitive aValue search
    /// 搜索一个Value，返回List中的索引
    // - 使用 O(n) 强力算法和区分大小写的 aValue 搜索
    function FindByValue(const aValue: RawUtf8): PtrInt;
    /// search for a Name, and delete its entry in the List if it exists
    /// 搜索名称，如果存在则删除其在列表中的条目
    function Delete(const aName: RawUtf8): boolean;
    /// search for a Value, and delete its entry in the List if it exists
    // - returns the number of deleted entries
    // - you may search for more than one match, by setting a >1 Limit value
    /// 搜索一个 Value，如果存在则删除其在 List 中的条目
    // - 返回已删除条目的数量
    // - 您可以通过设置 >1 的限制值来搜索多个匹配项
    function DeleteByValue(const aValue: RawUtf8; Limit: integer = 1): integer;
    /// search for a Name, return the associated Value as a UTF-8 string
    /// 搜索名称，以 UTF-8 字符串形式返回关联值
    function Value(const aName: RawUtf8; const aDefaultValue: RawUtf8 = ''): RawUtf8;
    /// search for a Name, return the associated Value as integer
    /// 搜索名称，以整数形式返回关联值
    function ValueInt(const aName: RawUtf8; const aDefaultValue: Int64 = 0): Int64;
    /// search for a Name, return the associated Value as boolean
    // - returns true only if the value is exactly '1'
    /// 搜索名称，返回关联的布尔值
    // - 仅当值恰好为“1”时才返回 true
    function ValueBool(const aName: RawUtf8): boolean;
    /// search for a Name, return the associated Value as an enumerate
    // - returns true and set aEnum if aName was found, and associated value
    // matched an aEnumTypeInfo item
    // - returns false if no match was found
    /// 搜索名称，以枚举形式返回关联的值
    // - 如果找到 aName 并且关联值与 aEnumTypeInfo 项匹配，则返回 true 并设置 aEnum
    // - 如果没有找到匹配则返回 false
    function ValueEnum(const aName: RawUtf8; aEnumTypeInfo: PRttiInfo;
      out aEnum; aEnumDefault: PtrUInt = 0): boolean; overload;
    /// returns all values, as CSV or INI content
    /// 返回所有值，作为 CSV 或 INI 内容
    function AsCsv(const KeySeparator: RawUtf8 = '=';
      const ValueSeparator: RawUtf8 = #13#10; const IgnoreKey: RawUtf8 = ''): RawUtf8;
    /// returns all values as a JSON object of string fields
    /// 将所有值作为字符串字段的 JSON 对象返回
    function AsJson: RawUtf8;
    /// fill the supplied two arrays of RawUtf8 with the stored values
    /// 用存储的值填充提供的两个 RawUtf8 数组
    procedure AsNameValues(out Names,Values: TRawUtf8DynArray);
    /// search for a Name, return the associated Value as variant
    // - returns null if the name was not found
    /// 搜索名称，返回关联的值作为变体
    // - 如果未找到名称则返回 null
    function ValueVariantOrNull(const aName: RawUtf8): variant;
    /// compute a TDocVariant document from the stored values
    // - output variant will be reset and filled as a TDocVariant instance,
    // ready to be serialized as a JSON object
    // - if there is no value stored (i.e. Count=0), set null
    /// 根据存储的值计算 TDocVariant 文档
    // - 输出变量将被重置并填充为 TDocVariant 实例，准备序列化为 JSON 对象
    // - 如果没有存储值（即 Count=0），则设置为 null
    procedure AsDocVariant(out DocVariant: variant;
      ExtendedJson: boolean = false; ValueAsString: boolean = true;
      AllowVarDouble: boolean = false); overload;
    /// compute a TDocVariant document from the stored values
    /// 根据存储的值计算 TDocVariant 文档
    function AsDocVariant(ExtendedJson: boolean = false;
      ValueAsString: boolean = true): variant; overload;
      {$ifdef HASINLINE}inline;{$endif}
    /// merge the stored values into a TDocVariant document
    // - existing properties would be updated, then new values will be added to
    // the supplied TDocVariant instance, ready to be serialized as a JSON object
    // - if ValueAsString is TRUE, values would be stored as string
    // - if ValueAsString is FALSE, numerical values would be identified by
    // IsString() and stored as such in the resulting TDocVariant
    // - if you let ChangedProps point to a TDocVariantData, it would contain
    // an object with the stored values, just like AsDocVariant
    // - returns the number of updated values in the TDocVariant, 0 if
    // no value was changed
    /// 将存储的值合并到 TDocVariant 文档中
    // - 现有属性将被更新，然后新值将添加到提供的 TDocVariant 实例中，准备序列化为 JSON 对象
    // - 如果 ValueAsString 为 TRUE，值将存储为字符串
    // - 如果 ValueAsString 为 FALSE，数值将由 IsString() 标识并按原样存储在结果 TDocVariant 中
    // - 如果您让 ChangedProps 指向 TDocVariantData，它将包含一个具有存储值的对象，就像 AsDocVariant 一样
    // - 返回 TDocVariant 中更新值的数量，如果没有值更改则返回 0
    function MergeDocVariant(var DocVariant: variant; ValueAsString: boolean;
      ChangedProps: PVariant = nil; ExtendedJson: boolean = false;
      AllowVarDouble: boolean = false): integer;
    /// returns true if the Init() method has been called
    /// 如果已调用 Init() 方法，则返回 true
    function Initialized: boolean;
    /// can be used to set all data from one BLOB memory buffer
    /// 可用于设置一个 BLOB 内存缓冲区中的所有数据
    procedure SetBlobDataPtr(aValue: pointer);
    /// can be used to set or retrieve all stored data as one BLOB content
    /// 可用于将所有存储的数据设置或检索为一个 BLOB 内容
    property BlobData: RawByteString
      read GetBlobData write SetBlobData;
    /// event triggerred after an item has just been added to the list
    /// 项目刚刚添加到列表后触发的事件
    property OnAfterAdd: TOnSynNameValueNotify
      read fOnAdd write fOnAdd;
    /// search for a Name, return the associated Value as a UTF-8 string
    // - returns '' if aName is not found in the stored keys
    /// 搜索名称，以 UTF-8 字符串形式返回关联值
    // - 如果在存储的键中找不到 aName，则返回 ''
    property Str[const aName: RawUtf8]: RawUtf8
      read GetStr; default;
    /// search for a Name, return the associated Value as integer
    // - returns 0 if aName is not found, or not a valid Int64 in the stored keys
    /// 搜索名称，以整数形式返回关联值
    // - 如果未找到 aName，或者存储的键中不是有效的 Int64，则返回 0
    property Int[const aName: RawUtf8]: Int64
      read GetInt;
    /// search for a Name, return the associated Value as boolean
    // - returns true if aName stores '1' as associated value
    /// 搜索名称，返回关联的布尔值
    // - 如果 aName 将“1”存储为关联值，则返回 true
    property Bool[const aName: RawUtf8]: boolean
      read GetBool;
  end;


  /// a reference pointer to a Name/Value RawUtf8 pairs storage
  // 指向名称/值 RawUtf8 对存储的引用指针
  PSynNameValue = ^TSynNameValue;

  /// implement a cache of some key/value pairs, e.g. to improve reading speed
  // - used e.g. by TSqlDataBase for caching the SELECT statements results in an
  // internal JSON format (which is faster than a query to the SQLite3 engine)
  // - internally make use of an efficient hashing algorithm for fast response
  // (i.e. TSynNameValue will use the TDynArrayHashed wrapper mechanism)
  // - this class is thread-safe if you use properly the associated Safe lock
  /// 实现一些键/值对的缓存，例如 提高阅读速度
  // - 例如使用 通过 TSqlDataBase 将 SELECT 语句结果缓存为内部 JSON 格式（这比对 SQLite3 引擎的查询更快）
  // - 内部使用高效的哈希算法来实现快速响应（即 TSynNameValue 将使用 TDynArrayHashed 包装器机制）
  // - 如果正确使用关联的安全锁，该类是线程安全的  
  TSynCache = class(TSynLocked)
  protected
    fFindLastKey: RawUtf8;
    fNameValue: TSynNameValue;
    fRamUsed: cardinal;
    fMaxRamUsed: cardinal;
    fTimeoutSeconds: cardinal;
    fTimeoutTix: cardinal;
    procedure ResetIfNeeded;
  public
    /// initialize the internal storage
    // - aMaxCacheRamUsed can set the maximum RAM to be used for values, in bytes
    // (default is 16 MB), after which the cache is flushed
    // - by default, key search is done case-insensitively, but you can specify
    // another option here
    // - by default, there is no timeout period, but you may specify a number of
    // seconds of inactivity (i.e. no Add call) after which the cache is flushed
    /// 初始化内部存储
    // - aMaxCacheRamUsed 可以设置用于值的最大 RAM，以字节为单位（默认为 16 MB），之后刷新缓存
    // - 默认情况下，键搜索不区分大小写，但您可以在此处指定另一个选项
    // - 默认情况下，没有超时期限，但您可以指定不活动的秒数（即没有 Add 调用），之后刷新缓存
    constructor Create(aMaxCacheRamUsed: cardinal = 16 shl 20;
      aCaseSensitive: boolean = false; aTimeoutSeconds: cardinal = 0); reintroduce;
    /// find a Key in the cache entries
    // - return '' if nothing found: you may call Add() just after to insert
    // the expected value in the cache
    // - return the associated Value otherwise, and the associated integer tag
    // if aResultTag address is supplied
    // - this method is not thread-safe, unless you call Safe.Lock before
    // calling Find(), and Safe.Unlock after calling Add()
    /// 在缓存条目中查找Key
    // - 如果没有找到任何内容，则返回 ''：您可以在将预期值插入到缓存中之后调用 Add()
    // - 否则返回关联的值，如果提供了结果标签地址则返回关联的整数标签
    // - 此方法不是线程安全的，除非您在调用 Find() 之前调用 Safe.Lock，并在调用 Add() 之后调用 Safe.Unlock
    function Find(const aKey: RawUtf8; aResultTag: PPtrInt = nil): RawUtf8;
    /// add a Key and its associated value (and tag) to the cache entries
    // - you MUST always call Find() with the associated Key first
    // - this method is not thread-safe, unless you call Safe.Lock before
    // calling Find(), and Safe.Unlock after calling Add()
    /// 将Key及其关联值（和标签）添加到缓存条目中
    // - 您必须始终首先使用关联的 Key 调用 Find()
    // - 此方法不是线程安全的，除非您在调用 Find() 之前调用
    procedure Add(const aValue: RawUtf8; aTag: PtrInt);
    /// add a Key/Value pair in the cache entries
    // - returns true if aKey was not existing yet, and aValue has been stored
    // - returns false if aKey did already exist in the internal cache, and
    // its entry has been updated with the supplied aValue/aTag
    // - this method is thread-safe, using the Safe locker of this instance
    /// 在缓存条目中添加键/值对
    // - 如果 aKey 尚不存在且 aValue 已存储，则返回 true
    // - 如果 aKey 已存在于内部缓存中，并且其条目已使用提供的 aValue/aTag 进行更新，则返回 false
    // - 该方法是线程安全的，使用该实例的 Safe locker
    function AddOrUpdate(const aKey, aValue: RawUtf8; aTag: PtrInt): boolean;
    /// called after a write access to the database to flush the cache
    // - set Count to 0
    // - release all cache memory
    // - returns TRUE if was flushed, i.e. if there was something in cache
    // - this method is thread-safe, using the Safe locker of this instance
    /// 对数据库进行写访问以刷新缓存后调用
    // - 将计数设置为 0
    // - 释放所有缓存
    // - 如果被刷新，即如果缓存中有东西，则返回 TRUE
    // - 该方法是线程安全的，使用该实例的 Safe locker    
    function Reset: boolean;
    /// number of entries in the cache
    /// 缓存中的条目数
    function Count: integer;
    /// access to the internal locker, for thread-safe process
    // - Find/Add methods calls should be protected as such:
    // ! cache.Safe.Lock;
    // ! try
    // !   ... cache.Find/cache.Add ...
    // ! finally
    // !   cache.Safe.Unlock;
    // ! end;
    /// 访问内部locker，用于线程安全进程
    // - Find/Add 方法调用应该受到这样的保护：
    // ! cache.Safe.Lock;
    // ! try
    // !   ... cache.Find/cache.Add ...
    // ! finally
    // !   cache.Safe.Unlock;
    // ! end;
    property Safe: PSynLocker
      read fSafe;
    /// the current global size of Values in RAM cache, in bytes
    /// RAM 缓存中 Values 的当前全局大小，以字节为单位
    property RamUsed: cardinal
      read fRamUsed;
    /// the maximum RAM to be used for values, in bytes
    // - the cache is flushed when ValueSize reaches this limit
    // - default is 16 MB (16 shl 20)
    /// 用于值的最大 RAM，以字节为单位
    // - 当 ValueSize 达到此限制时刷新缓存
    // - 默认为 16 MB (16 shl 20)
    property MaxRamUsed: cardinal
      read fMaxRamUsed;
    /// after how many seconds betwen Add() calls the cache should be flushed
    // - equals 0 by default, meaning no time out
    /// Add() 调用之间多少秒后应刷新缓存
    // - 默认等于 0，表示没有超时
    property TimeoutSeconds: cardinal
      read fTimeoutSeconds;
  end;


type
  /// implement binary persistence and JSON serialization (not deserialization)
  /// 实现二进制持久化和JSON序列化（不是反序列化）
  TSynPersistentStoreJson = class(TSynPersistentStore)
  protected
    // append "name" -> inherited should add properties to the JSON object
    // 追加“name” -> 继承应该向 JSON 对象添加属性
    procedure AddJson(W: TTextWriter); virtual;
  public
    /// serialize this instance as a JSON object
    /// 将此实例序列化为 JSON 对象
    function SaveToJson(reformat: TTextWriterJsonFormat = jsonCompact): RawUtf8;
  end;



{ *********** JSON-aware TSynDictionary Storage }
{ ********* JSON 感知的 TSynDictionary 存储 }
type
  /// exception raised during TSynDictionary process
  /// TSynDictionary 过程中引发异常
  ESynDictionary = class(ESynException);

  // internal flag, used only by TSynDictionary.InArray protected method
  // 内部标志，仅由 TSynDictionary.InArray 受保护方法使用
  TSynDictionaryInArray = (
    iaFind,
    iaFindAndDelete,
    iaFindAndUpdate,
    iaFindAndAddIfNotExisting,
    iaAdd,
    iaAddForced);

  /// tune TSynDictionary process depending on your use case
  // - doSingleThreaded will bypass Safe.Lock/UnLock call for better performance
  // if you are sure that this dictionary will be accessed from a single thread
  /// 根据您的用例调整 TSynDictionary 过程
  // - 如果您确定将从单个线程访问此字典，doSingleThreaded 将绕过 Safe.Lock/UnLock 调用以获得更好的性能
  TSynDictionaryOptions = set of (
    doSingleThreaded);

  /// event called by TSynDictionary.ForEach methods to iterate over stored items
  // - if the implementation method returns TRUE, will continue the loop
  // - if the implementation method returns FALSE, will stop values browsing
  // - aOpaque is a custom value specified at ForEach() method call
  /// TSynDictionary.ForEach 方法调用的事件以迭代存储的项目
  // - 如果实现方法返回TRUE，将继续循环
  // - 如果实现方法返回FALSE，将停止值浏览
  // - aOpaque 是在 ForEach() 方法调用中指定的自定义值
  TOnSynDictionary = function(const aKey; var aValue;
    aIndex, aCount: integer; aOpaque: pointer): boolean of object;

  /// event called by TSynDictionary.DeleteDeprecated
  // - called just before deletion: return false to by-pass this item
  /// TSynDictionary.DeleteDeprecated 调用的事件
  // - 在删除之前调用：返回 false 以绕过此项
  TOnSynDictionaryCanDelete = function(const aKey, aValue;
    aIndex: integer): boolean of object;

  /// thread-safe dictionary to store some values from associated keys
  // - will maintain a dynamic array of values, associated with a hash table
  // for the keys, so that setting or retrieving values would be O(1)
  // - thread-safe by default, since most methods are protected by a TSynLocker;
  // set the doSingleThreaded option if you don't need thread-safety
  // - TDynArray is a wrapper which does not store anything, whereas this class
  // is able to store both keys and values, and provide convenient methods to
  // access the stored data, including JSON serialization and binary storage
  /// 线程安全字典，用于存储关联键中的一些值
  // - 将维护一个动态值数组，与键的哈希表相关联，因此设置或检索值的时间复杂度为 O(1)
  // - 默认情况下是线程安全的，因为大多数方法都受 TSynLocker 保护； 如果不需要线程安全，请设置 doSingleThreaded 选项
  // - TDynArray 是一个不存储任何内容的包装器，而此类能够存储键和值，并提供方便的方法来访问存储的数据，包括 JSON 序列化和二进制存储
  TSynDictionary = class(TSynLocked)
  protected
    fKeys: TDynArrayHashed;
    fValues: TDynArray;
    fTimeOut: TCardinalDynArray;
    fTimeOuts: TDynArray;
    fCompressAlgo: TAlgoCompress;
    fOptions: TSynDictionaryOptions;
    fOnCanDelete: TOnSynDictionaryCanDelete;
    function InternalAddUpdate(aKey, aValue: pointer; aUpdate: boolean): integer;
    function InArray(const aKey, aArrayValue; aAction: TSynDictionaryInArray;
      aCompare: TDynArraySortCompare): boolean;
    procedure SetTimeouts;
    function ComputeNextTimeOut: cardinal;
    function KeyFullHash(const Elem): cardinal;
    function KeyFullCompare(const A, B): integer;
    function GetCapacity: integer;
    procedure SetCapacity(const Value: integer);
    function GetTimeOutSeconds: cardinal; {$ifdef FPC} inline; {$endif}
    procedure SetTimeOutSeconds(Value: cardinal);
  public
    /// initialize the dictionary storage, specifyng dynamic array keys/values
    // - aKeyTypeInfo should be a dynamic array TypeInfo() RTTI pointer, which
    // would store the keys within this TSynDictionary instance
    // - aValueTypeInfo should be a dynamic array TypeInfo() RTTI pointer, which
    // would store the values within this TSynDictionary instance
    // - by default, string keys would be searched following exact case, unless
    // aKeyCaseInsensitive is TRUE
    // - you can set an optional timeout period, in seconds - you should call
    // DeleteDeprecated periodically to search for deprecated items
    /// 初始化字典存储，指定动态数组键/值
    // - aKeyTypeInfo 应该是动态数组 TypeInfo() RTTI 指针，它将在此 TSynDictionary 实例中存储键
    // - aValueTypeInfo 应该是动态数组 TypeInfo() RTTI 指针，它将存储此 TSynDictionary 实例中的值
    // - 默认情况下，将按照确切的大小写搜索字符串键，除非 aKeyCaseInsensitive 为 TRUE
    // - 您可以设置一个可选的超时时间（以秒为单位） - 您应该定期调用DeleteDeprecated来搜索已弃用的项目
    constructor Create(aKeyTypeInfo, aValueTypeInfo: PRttiInfo;
      aKeyCaseInsensitive: boolean = false; aTimeoutSeconds: cardinal = 0;
      aCompressAlgo: TAlgoCompress = nil; aHasher: THasher = nil); reintroduce; virtual;
    /// finalize the storage
    // - would release all internal stored values
    /// 完成存储
    // - 将释放所有内部存储的值
    destructor Destroy; override;
    /// try to add a value associated with a primary key
    // - returns the index of the inserted item, -1 if aKey is already existing
    // - this method is thread-safe, since it will lock the instance
    /// 尝试添加与主键关联的值
    // - 返回插入项的索引，如果 aKey 已经存在则返回 -1
    // - 此方法是线程安全的，因为它将锁定实例
    function Add(const aKey, aValue): integer;
    /// store a value associated with a primary key
    // - returns the index of the matching item
    // - if aKey does not exist, a new entry is added
    // - if aKey does exist, the existing entry is overriden with aValue
    // - this method is thread-safe, since it will lock the instance
    /// 存储与主键关联的值
    // - 返回匹配项的索引
    // - 如果aKey不存在，则添加一个新条目
    // - 如果 aKey 确实存在，则现有条目将被 aValue 覆盖
    // - 此方法是线程安全的，因为它将锁定实例
    function AddOrUpdate(const aKey, aValue): integer;
    /// clear the value associated via aKey
    // - does not delete the entry, but reset its value
    // - returns the index of the matching item, -1 if aKey was not found
    // - this method is thread-safe, since it will lock the instance
    /// 清除通过aKey关联的值
    // - 不删除条目，但重置其值
    // - 返回匹配项的索引，如果未找到 aKey，则返回 -1
    // - 此方法是线程安全的，因为它将锁定实例
    function Clear(const aKey): integer;
    /// delete all key/value stored in the current instance
    /// 删除当前实例中存储的所有键/值
    procedure DeleteAll;
    /// delete a key/value association from its supplied aKey
    // - this would delete the entry, i.e. matching key and value pair
    // - returns the index of the deleted item, -1 if aKey was not found
    // - this method is thread-safe, since it will lock the instance
    /// 从提供的 aKey 中删除键/值关联
    // - 这将删除条目，即匹配的键和值对
    // - 返回已删除项的索引，如果未找到 aKey，则返回 -1
    // - 此方法是线程安全的，因为它将锁定实例
    function Delete(const aKey): integer;
    /// delete a key/value association from its internal index
    // - this method is not thread-safe: you should use fSafe.Lock/Unlock
    // e.g. then Find/FindValue to retrieve the index value
    /// 从其内部索引中删除键/值关联
    // - 这个方法不是线程安全的：你应该使用fSafe.Lock/Unlock。 然后 Find/FindValue 检索索引值
    function DeleteAt(aIndex: integer): boolean;
    /// search and delete all deprecated items according to TimeoutSeconds
    // - returns how many items have been deleted
    // - you can call this method very often: it will ensure that the
    // search process will take place at most once every second
    // - this method is thread-safe, but blocking during the process
    /// 根据TimeoutSeconds搜索并删除所有已弃用的项目
     // - 返回已删除的项目数
     // - 您可以经常调用此方法：它将确保搜索过程每秒最多发生一次
     // - 该方法是线程安全的，但在过程中会阻塞
    function DeleteDeprecated: integer;
    /// search of a primary key within the internal hashed dictionary
    // - returns the index of the matching item, -1 if aKey was not found
    // - if you want to access the value, you should use fSafe.Lock/Unlock:
    // consider using Exists or FindAndCopy thread-safe methods instead
    // - aUpdateTimeOut will update the associated timeout value of the entry
    /// 在内部哈希字典中搜索主键
     // - 返回匹配项的索引，如果未找到 aKey，则返回 -1
     // - 如果你想访问该值，你应该使用fSafe.Lock/Unlock：
     // 考虑使用 Exists 或 FindAndCopy 线程安全方法
     // - aUpdateTimeOut 将更新条目的关联超时值
    function Find(const aKey; aUpdateTimeOut: boolean = false): integer;
    /// search of a primary key within the internal hashed dictionary
    // - returns a pointer to the matching item, nil if aKey was not found
    // - if you want to access the value, you should use fSafe.Lock/Unlock:
    // consider using Exists or FindAndCopy thread-safe methods instead
    // - aUpdateTimeOut will update the associated timeout value of the entry
    /// 在内部哈希字典中搜索主键
     // - 返回指向匹配项的指针，如果未找到 aKey，则返回 nil
     // - 如果你想访问该值，你应该使用fSafe.Lock/Unlock：
     // 考虑使用 Exists 或 FindAndCopy 线程安全方法
     // - aUpdateTimeOut 将更新条目的关联超时值
    function FindValue(const aKey; aUpdateTimeOut: boolean = false;
      aIndex: PInteger = nil): pointer;
    /// search of a primary key within the internal hashed dictionary
    // - returns a pointer to the matching or already existing value item
    // - if you want to access the value, you should use fSafe.Lock/Unlock:
    // consider using Exists or FindAndCopy thread-safe methods instead
    // - will update the associated timeout value of the entry, if applying
    /// 在内部哈希字典中搜索主键
     // - 返回指向匹配或已经存在的值项的指针
     // - 如果你想访问该值，你应该使用fSafe.Lock/Unlock：考虑使用Exists或FindAndCopy线程安全方法
     // - 如果应用，将更新条目的关联超时值
    function FindValueOrAdd(const aKey; var added: boolean;
      aIndex: PInteger = nil): pointer;
    /// search of a stored value by its primary key, and return a local copy
    // - so this method is thread-safe
    // - returns TRUE if aKey was found, FALSE if no match exists
    // - will update the associated timeout value of the entry, unless
    // aUpdateTimeOut is set to false
    /// 通过主键搜索存储值，并返回本地副本
    // - 所以这个方法是线程安全的
    // - 如果找到aKey则返回TRUE，如果不存在匹配则返回FALSE
    // - 将更新条目的关联超时值，除非 aUpdateTimeOut 设置为 false
    function FindAndCopy(const aKey;
      var aValue; aUpdateTimeOut: boolean = true): boolean;
    /// search of a stored value by its primary key, then delete and return it
    // - returns TRUE if aKey was found, fill aValue with its content,
    // and delete the entry in the internal storage
    // - so this method is thread-safe
    // - returns FALSE if no match exists
    /// 通过主键搜索存储值，然后删除并返回
    // - 如果找到 aKey，则返回 TRUE，用其内容填充 aValue，并删除内部存储中的条目
    // - 所以这个方法是线程安全的
    // - 如果不存在匹配则返回 FALSE
    function FindAndExtract(const aKey; var aValue): boolean;
    /// search for a primary key presence
    // - returns TRUE if aKey was found, FALSE if no match exists
    // - this method is thread-safe
    /// 搜索主键是否存在
    // - 如果找到aKey则返回TRUE，如果不存在匹配则返回FALSE
    // - 该方法是线程安全的
    function Exists(const aKey): boolean;
    /// search for a value presence
    // - returns TRUE if aValue was found, FALSE if no match exists
    // - this method is thread-safe, but will use O(n) slow browsing
    /// 搜索存在值
     // - 如果找到aValue则返回TRUE，如果不存在匹配则返回FALSE
     // - 此方法是线程安全的，但会使用 O(n) 慢速浏览
    function ExistsValue(const aValue; aCompare: TDynArraySortCompare = nil): boolean;
    /// apply a specified event over all items stored in this dictionnary
    // - would browse the list in the adding order
    // - returns the number of times OnEach has been called
    // - this method is thread-safe, since it will lock the instance
    /// 对存储在该字典中的所有项目应用指定的事件
     // - 将按添加顺序浏览列表
     // - 返回 OnEach 被调用的次数
     // - 此方法是线程安全的，因为它将锁定实例
    function ForEach(const OnEach: TOnSynDictionary;
      Opaque: pointer = nil): integer; overload;
    /// apply a specified event over matching items stored in this dictionnary
    // - would browse the list in the adding order, comparing each key and/or
    // value item with the supplied comparison functions and aKey/aValue content
    // - returns the number of times OnMatch has been called, i.e. how many times
    // KeyCompare(aKey,Keys[#])=0 or ValueCompare(aValue,Values[#])=0
    // - this method is thread-safe, since it will lock the instance
    /// 对存储在该字典中的匹配项应用指定的事件
     // - 将按添加顺序浏览列表，将每个键和/或值项与提供的比较函数和 aKey/aValue 内容进行比较
     // - 返回 OnMatch 被调用的次数，即 KeyCompare(aKey,Keys[#])=0 或 ValueCompare(aValue,Values[#])=0 的次数
     // - 此方法是线程安全的，因为它将锁定实例
    function ForEach(const OnMatch: TOnSynDictionary;
      KeyCompare, ValueCompare: TDynArraySortCompare; const aKey, aValue;
      Opaque: pointer = nil): integer; overload;
    /// touch the entry timeout field so that it won't be deprecated sooner
    // - this method is not thread-safe, and is expected to be execute e.g.
    // from a ForEach() TOnSynDictionary callback
    /// 触摸输入超时字段，这样它就不会很快被弃用
     // - 此方法不是线程安全的，并且预计会执行，例如 来自 ForEach()
    procedure SetTimeoutAtIndex(aIndex: integer);
    /// search aArrayValue item in a dynamic-array value associated via aKey
    // - expect the stored value to be a dynamic array itself
    // - would search for aKey as primary key, then use TDynArray.Find
    // to delete any aArrayValue match in the associated dynamic array
    // - returns FALSE if Values is not a tkDynArray, or if aKey or aArrayValue
    // were not found
    // - this method is thread-safe, since it will lock the instance
    /// 在通过aKey关联的动态数组值中搜索aArrayValue项
     // - 期望存储的值本身是动态数组
     // - 将搜索 aKey 作为主键，然后使用 TDynArray.Find 删除关联动态数组中的任何 aArrayValue 匹配项
     // - 如果 Values 不是 tkDynArray，或者未找到 aKey 或 aArrayValue，则返回 FALSE
     // - 此方法是线程安全的，因为它将锁定实例
    function FindInArray(const aKey, aArrayValue;
      aCompare: TDynArraySortCompare = nil): boolean;
    /// search of a stored key by its associated key, and return a key local copy
    // - won't use any hashed index but RTTI TDynArray.IndexOf search over
    // over fValues() so is much slower than FindAndCopy() for huge arrays
    // - will update the associated timeout value of the entry, unless
    // aUpdateTimeOut is set to false
    // - this method is thread-safe
    // - returns TRUE if aValue was found, FALSE if no match exists
    /// 通过关联的键搜索存储的键，并返回键的本地副本
     // - 不会使用任何散列索引，但会使用 RTTI TDynArray.IndexOf 进行搜索。 对于大型数组，fValues() 比 FindAndCopy() 慢得多
     // - 将更新条目的关联超时值，除非 aUpdateTimeOut 设置为 false
     // - 该方法是线程安全的
     // - 如果找到aValue则返回TRUE，如果不存在匹配则返回FALSE
    function FindKeyFromValue(const aValue; out aKey;
      aUpdateTimeOut: boolean = true): boolean;
    /// add aArrayValue item within a dynamic-array value associated via aKey
    // - expect the stored value to be a dynamic array itself
    // - would search for aKey as primary key, then use TDynArray.Add
    // to add aArrayValue to the associated dynamic array
    // - returns FALSE if Values is not a tkDynArray, or if aKey was not found
    // - this method is thread-safe, since it will lock the instance
    /// 在通过aKey关联的动态数组值中添加aArrayValue项
     // - 期望存储的值本身是动态数组
     // - 将搜索 aKey 作为主键，然后使用 TDynArray.Add 将 aArrayValue 添加到关联的动态数组
     // - 如果 Values 不是 tkDynArray，或者未找到 aKey，则返回 FALSE
     // - 此方法是线程安全的，因为它将锁定实例
    function AddInArray(const aKey, aArrayValue;
      aCompare: TDynArraySortCompare = nil): boolean;
    /// add aArrayValue item within a dynamic-array value associated via aKey
    // - expect the stored value to be a dynamic array itself
    // - would search for aKey as primary key, create the entry if not found,
    //  then use TDynArray.Add to add aArrayValue to the associated dynamic array
    // - returns FALSE if Values is not a tkDynArray
    // - this method is thread-safe, since it will lock the instance
    /// 在通过aKey关联的动态数组值中添加aArrayValue项
     // - 期望存储的值本身是动态数组
     // - 将搜索 aKey 作为主键，如果未找到则创建条目，然后使用 TDynArray.Add 将 aArrayValue 添加到关联的动态数组
     // - 如果 Values 不是 tkDynArray，则返回 FALSE
     // - 此方法是线程安全的，因为它将锁定实例
    function AddInArrayForced(const aKey, aArrayValue;
      aCompare: TDynArraySortCompare = nil): boolean;
    /// add once aArrayValue within a dynamic-array value associated via aKey
    // - expect the stored value to be a dynamic array itself
    // - would search for aKey as primary key, then use
    // TDynArray.FindAndAddIfNotExisting to add once aArrayValue to the
    // associated dynamic array
    // - returns FALSE if Values is not a tkDynArray, or if aKey was not found
    // - this method is thread-safe, since it will lock the instance
    /// 在通过 aKey 关联的动态数组值中添加一次 aArrayValue
     // - 期望存储的值本身是动态数组
     // - 将搜索 aKey 作为主键，然后使用 TDynArray.FindAndAddIfNotExisting 将 aArrayValue 添加一次到关联的动态数组
     // - 如果 Values 不是 tkDynArray，或者未找到 aKey，则返回 FALSE
     // - 此方法是线程安全的，因为它将锁定实例
    function AddOnceInArray(const aKey, aArrayValue;
      aCompare: TDynArraySortCompare = nil): boolean;
    /// clear aArrayValue item of a dynamic-array value associated via aKey
    // - expect the stored value to be a dynamic array itself
    // - would search for aKey as primary key, then use TDynArray.FindAndDelete
    // to delete any aArrayValue match in the associated dynamic array
    // - returns FALSE if Values is not a tkDynArray, or if aKey or aArrayValue
    // were not found
    // - this method is thread-safe, since it will lock the instance
    /// 清除通过aKey关联的动态数组值的aArrayValue项
     // - 期望存储的值本身是动态数组
     // - 将搜索 aKey 作为主键，然后使用 TDynArray.FindAndDelete 删除关联动态数组中的任何 aArrayValue 匹配项
     // - 如果 Values 不是 tkDynArray，或者未找到 aKey 或 aArrayValue，则返回 FALSE
     // - 此方法是线程安全的，因为它将锁定实例
    function DeleteInArray(const aKey, aArrayValue;
      aCompare: TDynArraySortCompare = nil): boolean;
    /// replace aArrayValue item of a dynamic-array value associated via aKey
    // - expect the stored value to be a dynamic array itself
    // - would search for aKey as primary key, then use TDynArray.FindAndUpdate
    // to delete any aArrayValue match in the associated dynamic array
    // - returns FALSE if Values is not a tkDynArray, or if aKey or aArrayValue were
    // not found
    // - this method is thread-safe, since it will lock the instance
    /// 替换通过aKey关联的动态数组值的aArrayValue项
     // - 期望存储的值本身是动态数组
     // - 将搜索 aKey 作为主键，然后使用 TDynArray.FindAndUpdate 删除关联动态数组中的任何 aArrayValue 匹配项
     // - 如果 Values 不是 tkDynArray，或者未找到 aKey 或 aArrayValue，则返回 FALSE
     // - 此方法是线程安全的，因为它将锁定实例
    function UpdateInArray(const aKey, aArrayValue;
      aCompare: TDynArraySortCompare = nil): boolean;
    /// make a copy of the stored values
    // - this method is thread-safe, since it will lock the instance during copy
    // - resulting length(Dest) will match the exact values count
    // - T*ObjArray will be reallocated and copied by content (using a temporary
    // JSON serialization), unless ObjArrayByRef is true and pointers are copied
    /// 复制存储的值
     // - 此方法是线程安全的，因为它将在复制期间锁定实例
     // - 结果长度（Dest）将匹配精确值计数
     // - T*ObjArray 将按内容重新分配和复制（使用临时 JSON 序列化），除非 ObjArrayByRef 为 true 并且复制指针
    procedure CopyValues(out Dest; ObjArrayByRef: boolean = false);
    /// serialize the content as a "key":value JSON object
    /// 将内容序列化为“key”:value JSON对象
    procedure SaveToJson(
      W: TTextWriter; EnumSetsAsText: boolean = false); overload;
    /// serialize the content as a "key":value JSON object
    /// 将内容序列化为“key”:value JSON对象
    function SaveToJson(
      EnumSetsAsText: boolean = false): RawUtf8; overload;
    /// serialize the Values[] as a JSON array
    /// 将 Values[] 序列化为 JSON 数组
    function SaveValuesToJson(EnumSetsAsText: boolean = false): RawUtf8;
    /// unserialize the content from "key":value JSON object
    // - if the JSON input may not be correct (i.e. if not coming from SaveToJson),
    // you may set EnsureNoKeyCollision=TRUE for a slow but safe keys validation
    /// 反序列化“key”:value JSON对象中的内容
     // - 如果 JSON 输入可能不正确（即，如果不是来自 SaveToJson），您可以设置 EnsureNoKeyCollision=TRUE 进行缓慢但安全的密钥验证
    function LoadFromJson(const Json: RawUtf8;
      CustomVariantOptions: PDocVariantOptions = nil): boolean; overload;
    /// unserialize the content from "key":value JSON object
    // - note that input JSON buffer is not modified in place: no need to create
    // a temporary copy if the buffer is about to be re-used
    /// 反序列化“key”:value JSON对象中的内容
     // - 请注意，输入 JSON 缓冲区未就地修改：如果要重新使用缓冲区，则无需创建临时副本
    function LoadFromJson(Json: PUtf8Char;
      CustomVariantOptions: PDocVariantOptions = nil): boolean; overload;
    /// save the content as SynLZ-compressed raw binary data
    // - warning: this format is tied to the values low-level RTTI, so if you
    // change the value/key type definitions, LoadFromBinary() would fail
    /// 将内容保存为 SynLZ 压缩的原始二进制数据
     // - 警告：此格式与低级 RTTI 值相关，因此如果更改值/键类型定义，LoadFromBinary() 将失败
    function SaveToBinary(NoCompression: boolean = false;
      Algo: TAlgoCompress = nil): RawByteString;
    /// load the content from SynLZ-compressed raw binary data
    // - as previously saved by SaveToBinary method
    /// 从 SynLZ 压缩的原始二进制数据加载内容
     // - 正如之前通过 SaveToBinary 方法保存的那样
    function LoadFromBinary(const binary: RawByteString): boolean;
    /// can be assigned to OnCanDeleteDeprecated to check TSynPersistentLock(aValue).Safe.IsLocked
    /// 可以赋值给OnCanDeleteDeprecated来检查TSynPersistentLock(aValue).Safe.IsLocked
    class function OnCanDeleteSynPersistentLock(
      const aKey, aValue; aIndex: integer): boolean;
    /// can be assigned to OnCanDeleteDeprecated to check TSynPersistentLock(aValue).Safe.IsLocked
    /// 可以赋值给OnCanDeleteDeprecated来检查TSynPersistentLock(aValue).Safe.IsLocked
    class function OnCanDeleteSynPersistentLocked(
      const aKey, aValue; aIndex: integer): boolean;
    /// returns how many items are currently stored in this dictionary
    // - this method is thread-safe
    /// 返回当前字典中存储了多少项
     // - 该方法是线程安全的
    function Count: integer;
    /// fast returns how many items are currently stored in this dictionary
    // - this method is NOT thread-safe so should be protected by fSafe.Lock/UnLock
    /// 快速返回当前字典中存储了多少项
     // - 此方法不是线程安全的，因此应受 fSafe.Lock/UnLock 保护
    function RawCount: integer;
      {$ifdef HASINLINE}inline;{$endif}
    /// direct access to the primary key identifiers
    // - if you want to access the keys, you should use fSafe.Lock/Unlock
    /// 直接获取主键标识符
     // - 如果你想访问密钥，你应该使用fSafe.Lock/Unlock
    property Keys: TDynArrayHashed
      read fKeys;
    /// direct access to the associated stored values
    // - if you want to access the values, you should use fSafe.Lock/Unlock
    /// 直接访问关联的存储值
     // - 如果你想访问这些值，你应该使用fSafe.Lock/Unlock
    property Values: TDynArray
      read fValues;
    /// defines how many items are currently stored in Keys/Values internal arrays
    // - if you set a maximum size of this store (even a rough size), Add() are
    // likely to be up to twice faster than letting the table grow by chunks
    /// 定义当前有多少项存储在 Keys/Values 内部数组中
     // - 如果您设置此存储的最大大小（即使是粗略大小），Add() 可能比让表按块增长快两倍
    property Capacity: integer
      read GetCapacity write SetCapacity;
    /// direct low-level access to the internal access tick (GetTickCount64 shr 10)
    // - may be nil if TimeOutSeconds=0
    ///直接低级访问内部访问tick(GetTickCount64 shr 10)
     // - 如果 TimeOutSeconds=0 则可能为零
    property TimeOut: TCardinalDynArray
      read fTimeOut;
    /// returns the aTimeOutSeconds parameter value, as specified to Create()
    // - warning: setting a new timeout will clear all previous content
    /// 返回 aTimeOutSeconds 参数值，如 Create() 指定的那样
     // - 警告：设置新的超时将清除所有以前的内容
    property TimeOutSeconds: cardinal
      read GetTimeOutSeconds write SetTimeOutSeconds;
    /// the compression algorithm used for binary serialization
    /// 用于二进制序列化的压缩算法
    property CompressAlgo: TAlgoCompress
      read fCompressAlgo write fCompressAlgo;
    /// callback to by-pass DeleteDeprecated deletion by returning false
    // - can be assigned e.g. to OnCanDeleteSynPersistentLock if Value is a
    // TSynPersistentLock instance, to avoid any potential access violation
    /// 通过返回 false 来绕过 DeleteDeprecated 删除的回调
     // - 可以被赋值，例如 如果 Value 是 TSynPersistentLock 实例，则为 OnCanDeleteSynPercientLock，以避免任何潜在的访问冲突
    property OnCanDeleteDeprecated: TOnSynDictionaryCanDelete
      read fOnCanDelete write fOnCanDelete;
    /// can tune TSynDictionary process depending on your use case
    // - warning: any performance impact should always be monitored, not guessed
    /// 可以根据您的用例调整 TSynDictionary 过程
     // - 警告：任何性能影响都应始终受到监控，而不是猜测
    property Options: TSynDictionaryOptions
      read fOptions write fOptions;
  end;



{ ********** Low-level JSON Serialization for any kind of Values }
{ ********** 适用于任何类型值的低级 JSON 序列化 }

type
  /// internal stack-allocated structure for nested serialization
  // - defined here for low-level use of TRttiJsonSave functions
  /// 用于嵌套序列化的内部堆栈分配结构
   // - 此处定义用于 TRttiJsonSave 函数的低级使用
  TJsonSaveContext = object
  protected
    W: TTextWriter;
    Options: TTextWriterWriteObjectOptions;
    Info: TRttiCustom;
    Prop: PRttiCustomProp;
    procedure Add64(Value: PInt64; UnSigned: boolean);
    procedure AddShort(PS: PShortString);
    procedure AddShortBoolean(PS: PShortString; Value: boolean);
    procedure AddDateTime(Value: PDateTime; WithMS: boolean);
  public
    /// initialize this low-level context
    /// 初始化这个低级上下文
    procedure Init(WR: TTextWriter;
      WriteOptions: TTextWriterWriteObjectOptions; Rtti: TRttiCustom);
      {$ifdef HASINLINE}inline;{$endif}
  end;

  /// internal function handler for JSON persistence of any TRttiParserType value
  // - i.e. the kind of functions called via PT_JSONSAVE[] lookup table
  /// 用于任何 TRttiParserType 值的 JSON 持久化的内部函数处理程序
   // - 即通过 PT_JSONSAVE[] 查找表调用的函数类型
  TRttiJsonSave = procedure(Data: pointer; const Ctxt: TJsonSaveContext);


{ ********** Low-level JSON Unserialization for any kind of Values }
{ ********** 任何类型值的低级 JSON 反序列化 }

type
  /// available options for JSON parsing process
  // - by default, parsing will fail if a JSON field name is not part of the
  // object published properties, unless jpoIgnoreUnknownProperty is defined -
  // this option will also ignore read-only properties (i.e. with only a getter)
  // - by default, function will check that the supplied JSON value will
  // be a JSON string when the property is a string, unless jpoIgnoreStringType
  // is defined and JSON numbers are accepted and stored as text
  // - by default any unexpected value for enumerations will be marked as
  // invalid, unless jpoIgnoreUnknownEnum is defined, so that in such case the
  // ordinal 0 value is left, and loading continues
  // - by default, only simple kind of variant types (string/numbers) are
  // handled: set jpoHandleCustomVariants if you want to handle any custom -
  // in this case , it will handle direct JSON [array] of {object}: but if you
  // also define jpoHandleCustomVariantsWithinString, it will also try to
  // un-escape a JSON string first, i.e. handle "[array]" or "{object}" content
  // (may be used e.g. when JSON has been retrieved from a database TEXT column)
  // - by default, a temporary instance will be created if a published field
  // has a setter, and the instance is expected to be released later by the
  // owner class: set jpoSetterExpectsToFreeTempInstance to let JsonParser
  // (and TPropInfo.ClassFromJson) release it when the setter returns, and
  // jpoSetterNoCreate to avoid the published field instance creation
  // - set jpoAllowInt64Hex to let Int64/QWord fields accept hexadecimal string
  // (as generated e.g. via the woInt64AsHex option)
  // - by default, double values won't be stored as variant values, unless
  // jpoAllowDouble is set - see also dvoAllowDoubleValue in TDocVariantOptions
  // - jpoObjectListClassNameGlobalFindClass would also search for "ClassName":
  // TObjectList serialized field with the global Classes.FindClass() function
  // - null will release any class instance, unless jpoNullDontReleaseObjectInstance
  // is set which will leave the instance untouched
  // - values will be left untouched before parsing, unless jpoClearValues
  // is defined, to void existing record fields or class published properties
  /// JSON 解析过程的可用选项
   // - 默认情况下，如果 JSON 字段名称不是对象发布属性的一部分，则解析将失败，除非定义了 jpoIgnoreUnknownProperty - 此选项还将忽略只读属性（即仅具有 getter）
   // - 默认情况下，当属性是字符串时，函数将检查提供的 JSON 值是否为 JSON 字符串，除非定义了 jpoIgnoreStringType 并且接受 JSON 数字并将其存储为文本
   // - 默认情况下，任何意外的枚举值都将被标记为无效，除非定义了 jpoIgnoreUnknownEnum，因此在这种情况下，将保留序数 0 值，并继续加载
   // - 默认情况下，仅处理简单类型的变体类型（字符串/数字）：如果您想处理任何自定义，请设置 jpoHandleCustomVariants - 在这种情况下，它将处理 {object} 的直接 JSON [array]：但如果您 还定义 jpoHandleCustomVariantsWithinString，它也会首先尝试取消转义 JSON 字符串，即处理“[array]”或“{object}”内容（例如，当从数据库 TEXT 列检索 JSON 时可以使用）
   // - 默认情况下，如果已发布字段具有 setter，则将创建一个临时实例，并且该实例预计稍后由所有者类释放：设置 jpoSetterExpectsToFreeTempInstance 以让 JsonParser（和 TPropInfo.ClassFromJson）在 setter 时释放它 返回，并 jpoSetterNoCreate 以避免创建已发布的字段实例
   // - 设置 jpoAllowInt64Hex 让 Int64/QWord 字段接受十六进制字符串（例如通过 woInt64AsHex 选项生成）
   // - 默认情况下，双精度值不会存储为变量值，除非设置了 jpoAllowDouble - 另请参阅 TDocVariantOptions 中的 dvoAllowDoubleValue
   // - jpoObjectListClassNameGlobalFindClass 还将使用全局 Classes.FindClass() 函数搜索“ClassName”：TObjectList 序列化字段
   // - null 将释放任何类实例，除非设置了 jpoNullDontReleaseObjectInstance，这将使实例保持不变
   // - 在解析之前，值将保持不变，除非定义了 jpoClearValues，以无效现有记录字段或类发布的属性
  TJsonParserOption = (
    jpoIgnoreUnknownProperty,
    jpoIgnoreStringType,
    jpoIgnoreUnknownEnum,
    jpoHandleCustomVariants,
    jpoHandleCustomVariantsWithinString,
    jpoSetterExpectsToFreeTempInstance,
    jpoSetterNoCreate,
    jpoAllowInt64Hex,
    jpoAllowDouble,
    jpoObjectListClassNameGlobalFindClass,
    jpoNullDontReleaseObjectInstance,
    jpoClearValues);

  /// set of options for JsonParser() parsing process
  /// JsonParser() 解析过程的选项集
  TJsonParserOptions = set of TJsonParserOption;

  /// efficient execution context of the JSON parser
  // - defined here for low-level use of TRttiJsonLoad functions
  /// JSON解析器的高效执行上下文
   // - 此处定义用于 TRttiJsonLoad 函数的低级使用
  TJsonParserContext = object
  public
    /// current position in the JSON input
    /// JSON 输入中的当前位置
    Json: PUtf8Char;
    /// true if the last parsing succeeded
    /// 如果最后一次解析成功则为 true
    Valid: boolean;
    /// the last parsed character, just before current JSON
    /// 最后解析的字符，就在当前 JSON 之前
    EndOfObject: AnsiChar;
    /// customize parsing
    /// 自定义解析
    Options: TJsonParserOptions;
    /// how TDocVariant should be created
    /// 应如何创建 TDocVariant
    CustomVariant: PDocVariantOptions;
    /// contains the current value RTTI
    /// 包含当前值 RTTI
    Info: TRttiCustom;
    /// contains the current property value RTTI
    /// 包含当前属性值RTTI
    Prop: PRttiCustomProp;
    /// force the item class when reading a TObjectList without "ClassName":...
    /// 读取没有“ClassName”的 TObjectList 时强制项目类：...
    ObjectListItem: TRttiCustom;
    /// ParseNext unserialized value
    /// ParseNext 未序列化的值
    Value: PUtf8Char;
    /// ParseNext unserialized value length
    /// ParseNext 非序列化值长度
    ValueLen: integer;
    /// if ParseNext unserialized a JSON string
    /// 如果 ParseNext 反序列化 JSON 字符串
    WasString: boolean;
    /// TDocVariant initialization options
    /// TDocVariant 初始化选项
    DVO: TDocVariantOptions;
    /// initialize this unserialization context
    /// 初始化这个反序列化上下文
    procedure Init(P: PUtf8Char; Rtti: TRttiCustom; O: TJsonParserOptions;
      CV: PDocVariantOptions; ObjectListItemClass: TClass);
    /// call GetJsonField() to retrieve the next JSON value
    // - on success, return true and set Value/ValueLen and WasString fields
    /// 调用 GetJsonField() 检索下一个 JSON 值
     // - 成功时，返回 true 并设置 Value/ValueLen 和 WasString 字段
    function ParseNext: boolean;
      {$ifdef HASINLINE}inline;{$endif}
    /// retrieve the next JSON value as UTF-8 text
    /// 以 UTF-8 文本形式检索下一个 JSON 值
    function ParseUtf8: RawUtf8;
    /// retrieve the next JSON value as VCL string text
    /// 检索下一个 JSON 值作为 VCL 字符串文本
    function ParseString: string;
    /// retrieve the next JSON value as integer
    /// 以整数形式检索下一个 JSON 值
    function ParseInteger: Int64;
    /// set the EndOfObject field of a JSON buffer, just like GetJsonField() does
    // - to be called whan a JSON object or JSON array has been manually parsed
    /// 设置 JSON 缓冲区的 EndOfObject 字段，就像 GetJsonField() 一样
     // - 当手动解析 JSON 对象或 JSON 数组时调用
    procedure ParseEndOfObject;
      {$ifdef HASINLINE}inline;{$endif}
    /// parse a 'null' value from JSON buffer
    /// 从 JSON 缓冲区解析“null”值
    function ParseNull: boolean;
      {$ifdef HASINLINE}inline;{$endif}
    /// parse initial '[' token from JSON buffer
    // - once all the nested values have been read, call ParseEndOfObject
    /// 从 JSON 缓冲区解析初始 '[' 标记
     // - 读取所有嵌套值后，调用 ParseEndOfObject
    function ParseArray: boolean;
    /// parse a JSON object from the buffer into a
    // - if ObjectListItem was not defined, expect the JSON input to start as
    // '{"ClassName":"TMyClass",...}'
    /// 将缓冲区中的 JSON 对象解析为
     // - 如果未定义 ObjectListItem，则期望 JSON 输入以 '{"ClassName":"TMyClass",...}' 开头
    function ParseNewObject: TObject;
      {$ifdef HASINLINE}inline;{$endif}
    /// wrapper around JsonDecode() to easily get JSON object values
    /// JsonDecode() 的包装器以轻松获取 JSON 对象值
    function ParseObject(const Names: array of RawUtf8;
      Values: PValuePUtf8CharArray;
      HandleValuesAsObjectOrArray: boolean = false): boolean;
    /// parse a property value, properly calling any setter
    /// 解析属性值，正确调用任何设置器
    procedure ParsePropComplex(Data: pointer);
  end;

  PJsonParserContext = ^TJsonParserContext;

  /// internal function handler for JSON reading of any TRttiParserType value
  /// 用于读取任何 TRttiParserType 值的 JSON 的内部函数处理程序
  TRttiJsonLoad = procedure(Data: pointer; var Ctxt: TJsonParserContext);


var
  /// default options for the JSON parser
  // - as supplied to LoadJson() with Tolerant=false
  // - defined as var, not as const, to allow process-wide override
  /// JSON 解析器的默认选项
   // - 提供给 LoadJson() 且 Tolerant=false
   // - 定义为 var，而不是 const，以允许进程范围覆盖
  JSONPARSER_DEFAULTOPTIONS: TJsonParserOptions = [];

  /// some open-minded options for the JSON parser
  // - as supplied to LoadJson() with Tolerant=true
  // - won't block JSON unserialization due to some minor unexpected values
  // - used e.g. by TObjArraySerializer.CustomReader and
  // TInterfacedObjectFake.FakeCall/TServiceMethodExecute.ExecuteJson methods
  // - defined as var, not as const, to allow process-wide override
  /// JSON 解析器的一些开放选项
   // - 提供给 LoadJson() 且 Tolerant=true
   // - 不会因为一些小的意外值而阻止 JSON 反序列化
   // - 例如使用 通过 TObjArraySerializer.CustomReader 和 TInterfacedObjectFake.FakeCall/TServiceMethodExecute.ExecuteJson 方法
   // - 定义为 var，而不是 const，以允许进程范围覆盖
  JSONPARSER_TOLERANTOPTIONS: TJsonParserOptions =
    [jpoHandleCustomVariants, jpoIgnoreUnknownEnum,
     jpoIgnoreUnknownProperty, jpoIgnoreStringType, jpoAllowInt64Hex];

  /// access default (false) or tolerant (true) JSON parser options
  // - to be used as JSONPARSER_DEFAULTORTOLERANTOPTIONS[tolerant]
  /// 访问默认 (false) 或宽容 (true) JSON 解析器选项
   // - 用作 JSONPARSER_DEFAULTORTOLERANTOPTIONS[宽容]
  JSONPARSER_DEFAULTORTOLERANTOPTIONS: array[boolean] of TJsonParserOptions = (
    [],
    [jpoHandleCustomVariants, jpoIgnoreUnknownEnum,
     jpoIgnoreUnknownProperty, jpoIgnoreStringType, jpoAllowInt64Hex]);

{$ifndef PUREMORMOT2}
// backward compatibility types redirections
// 向后兼容类型重定向

type
  TJsonToObjectOption = TJsonParserOption;
  TJsonToObjectOptions = TJsonParserOptions;

const
  j2oSQLRawBlobAsBase64 = woRawBlobAsBase64;
  j2oIgnoreUnknownProperty = jpoIgnoreUnknownProperty;
  j2oIgnoreStringType = jpoIgnoreStringType;
  j2oIgnoreUnknownEnum = jpoIgnoreUnknownEnum;
  j2oHandleCustomVariants = jpoHandleCustomVariants;
  j2oHandleCustomVariantsWithinString = jpoHandleCustomVariantsWithinString;
  j2oSetterExpectsToFreeTempInstance = jpoSetterExpectsToFreeTempInstance;
  j2oSetterNoCreate = jpoSetterNoCreate;
  j2oAllowInt64Hex = jpoAllowInt64Hex;

const
  JSONTOOBJECT_TOLERANTOPTIONS: TJsonParserOptions =
    [jpoHandleCustomVariants, jpoIgnoreUnknownEnum,
     jpoIgnoreUnknownProperty, jpoIgnoreStringType, jpoAllowInt64Hex];

{$endif PUREMORMOT2}


{ ********** Custom JSON Serialization }
{ ********** 自定义 JSON 序列化 }

type
  /// the callback signature used by TRttiJson for serializing JSON data
  // - Data^ should be written into W, with the supplied Options
  /// TRttiJson 用于序列化 JSON 数据的回调签名
   // - Data^ 应使用提供的选项写入 W 中
  TOnRttiJsonWrite = procedure(W: TTextWriter; Data: pointer;
    Options: TTextWriterWriteObjectOptions) of object;

  /// the callback signature used by TRttiJson for unserializing JSON data
  // - set Context.Valid=true if Context.JSON has been parsed into Data^
  /// TRttiJson 用于反序列化 JSON 数据的回调签名
   // - 如果 Context.JSON 已解析为 Data^，则设置 Context.Valid=true
  TOnRttiJsonRead = procedure(var Context: TJsonParserContext;
    Data: pointer) of object;

  /// the callback signature used by TRttiJson for serializing JSON classes
  // - Instance should be written into W, with the supplied Options
  // - is in fact a convenient alias to the TOnRttiJsonWrite callback
  /// TRttiJson 用于序列化 JSON 类的回调签名
   // - 实例应使用提供的选项写入 W 中
   // - 实际上是 TOnRttiJsonWrite 回调的一个方便的别名
  TOnClassJsonWrite = procedure(W: TTextWriter; Instance: TObject;
    Options: TTextWriterWriteObjectOptions) of object;

  /// the callback signature used by TRttiJson for unserializing JSON classes
  // - set Context.Valid=true if Context.JSON has been parsed into Instance
  // - is in fact a convenient alias to the TOnRttiJsonRead callback
  /// TRttiJson 用于反序列化 JSON 类的回调签名
   // - 如果 Context.JSON 已解析为 Instance，则设置 Context.Valid=true
   // - 实际上是 TOnRttiJsonRead 回调的一个方便的别名
  TOnClassJsonRead = procedure(var Context: TJsonParserContext;
    Instance: TObject) of object;

  /// JSON-aware TRttiCustom class - used for global RttiCustom: TRttiCustomList
  /// JSON 感知的 TRttiCustom 类 - 用于全局 RttiCustom：TRttiCustomList
  TRttiJson = class(TRttiCustom)
  protected
    fCompare: array[boolean] of TRttiCompare;
    fIncludeReadOptions: TJsonParserOptions;
    fIncludeWriteOptions: TTextWriterWriteObjectOptions;
    // overriden for proper JSON process - set fJsonSave and fJsonLoad
    // 覆盖正确的 JSON 过程 - 设置 fJsonSave 和 fJsonLoad
    function SetParserType(aParser: TRttiParserType;
      aParserComplex: TRttiParserComplexType): TRttiCustom; override;
  public
    /// simple wrapper around TRttiJsonSave(fJsonSave)
    /// TRttiJsonSave(fJsonSave) 的简单包装
    procedure RawSaveJson(Data: pointer; const Ctxt: TJsonSaveContext);
      {$ifdef HASINLINE}inline;{$endif}
    /// simple wrapper around TRttiJsonLoad(fJsonLoad)
    /// TRttiJsonLoad(fJsonLoad) 的简单包装
    procedure RawLoadJson(Data: pointer; var Ctxt: TJsonParserContext);
      {$ifdef HASINLINE}inline;{$endif}
    /// create and parse a new TObject instance of this rkClass
    /// 创建并解析此 rkClass 的新 TObject 实例
    function ParseNewInstance(var Context: TJsonParserContext): TObject;
    /// compare two stored values of this type
    /// 比较该类型的两个存储值
    function ValueCompare(Data, Other: pointer; CaseInsensitive: boolean): integer; override;
    /// fill a variant with a stored value of this type
    /// 用该类型的存储值填充变体
    function ValueToVariant(Data: pointer; out Dest: TVarData): PtrInt; override;
    /// unserialize some JSON input into Data^
    /// 将一些 JSON 输入反序列化到 Data^
    procedure ValueLoadJson(Data: pointer; var Json: PUtf8Char; EndOfObject: PUtf8Char;
      ParserOptions: TJsonParserOptions; CustomVariantOptions: PDocVariantOptions;
      ObjectListItemClass: TClass = nil);
    /// efficient search of TRttiJson from a given RTTI TypeInfo()
    // - to be used instead of Rtti.Find() to return directly the TRttiJson instance
    /// 从给定的 RTTI TypeInfo() 高效搜索 TRttiJson
     // - 用于代替 Rtti.Find() 直接返回 TRttiJson 实例
    class function Find(Info: PRttiInfo): TRttiJson;
      {$ifdef HASINLINE}inline;{$endif}
    /// register a custom callback for JSON serialization of a given TypeInfo()
    // - for a dynamic array, will customize the item serialization callbacks
    // - replace deprecated TJsonSerializer.RegisterCustomSerializer() method
    /// 为给定 TypeInfo() 的 JSON 序列化注册自定义回调
     // - 对于动态数组，将自定义项目序列化回调
     // - 替换已弃用的 TJsonSerializer.RegisterCustomSerializer() 方法
    class function RegisterCustomSerializer(Info: PRttiInfo;
      const Reader: TOnRttiJsonRead; const Writer: TOnRttiJsonWrite): TRttiJson;
    /// unregister any custom callback for JSON serialization of a given TypeInfo()
    // - will also work after RegisterFromText()
    /// 取消注册给定 TypeInfo() 的 JSON 序列化的任何自定义回调
     // - 也将在 RegisterFromText() 之后工作
    class function UnRegisterCustomSerializer(Info: PRttiInfo): TRttiJson;
    /// register a custom callback for JSON serialization of a given class
    // - replace deprecated TJsonSerializer.RegisterCustomSerializer() method
    /// 为给定类的 JSON 序列化注册自定义回调
     // - 替换已弃用的 TJsonSerializer.RegisterCustomSerializer() 方法
    class function RegisterCustomSerializerClass(ObjectClass: TClass;
      const Reader: TOnClassJsonRead; const Writer: TOnClassJsonWrite): TRttiJson;
    /// unregister any custom callback for JSON serialization of a given class
    /// 取消注册给定类的 JSON 序列化的任何自定义回调
    class function UnRegisterCustomSerializerClass(ObjectClass: TClass): TRttiJson;
    /// register TypeInfo() custom JSON serialization for a given dynamic
    // array or record
    // - to be used instead of homonomous Rtti.RegisterFromText() to supply
    // an additional set of serialization/unserialization JSON options
    /// 为给定的动态数组或记录注册 TypeInfo() 自定义 JSON 序列化
     // - 用于代替同名 Rtti.RegisterFromText() 来提供一组附加的序列化/反序列化 JSON 选项
    class function RegisterFromText(DynArrayOrRecord: PRttiInfo;
      const RttiDefinition: RawUtf8;
      IncludeReadOptions: TJsonParserOptions;
      IncludeWriteOptions: TTextWriterWriteObjectOptions): TRttiJson;
    /// define an additional set of unserialization JSON options
    // - is included for this type to the supplied TJsonParserOptions
    /// 定义一组附加的反序列化 JSON 选项
     // - 包含此类型到提供的 TJsonParserOptions
    property IncludeReadOptions: TJsonParserOptions
      read fIncludeReadOptions write fIncludeReadOptions;
    /// define an additional set of serialization JSON options
    // - is included for this type to the supplied TTextWriterWriteObjectOptions
    /// 定义一组附加的序列化 JSON 选项
     // - 包含此类型到提供的 TTextWriterWriteObjectOptions
    property IncludeWriteOptions: TTextWriterWriteObjectOptions
      read fIncludeWriteOptions write fIncludeWriteOptions;
  end;


{ ********** JSON Serialization Wrapper Functions }
{ ********** JSON 序列化包装函数 }

var
  /// the options used by TObjArraySerializer, TInterfacedObjectFake and
  // TServiceMethodExecute when serializing values as JSON
  // - used as DEFAULT_WRITEOPTIONS[DontStoreVoidJson]
  // - you can modify this global variable to customize the whole process
  /// 将值序列化为 JSON 时 TObjArraySerializer、TInterfacedObjectFake 和 TServiceMethodExecute 使用的选项
   // - 用作 DEFAULT_WRITEOPTIONS[DontStoreVoidJson]
   // - 您可以修改此全局变量来自定义整个过程
  DEFAULT_WRITEOPTIONS: array[boolean] of TTextWriterWriteObjectOptions = (
    [woDontStoreDefault, woRawBlobAsBase64],
    [woDontStoreDefault, woDontStoreVoid, woRawBlobAsBase64]);

  /// the options used by TSynJsonFileSettings.SaveIfNeeded
  // - you can modify this global variable to customize the whole process
  /// TSynJsonFileSettings.SaveIfNeeded 使用的选项
   // - 您可以修改此全局变量来自定义整个过程
  SETTINGS_WRITEOPTIONS: TTextWriterWriteObjectOptions =
    [woHumanReadable, woStoreStoredFalse, woHumanReadableFullSetsAsStar,
     woHumanReadableEnumSetAsComment, woInt64AsHex];

  /// the options used by TServiceFactoryServer.OnLogRestExecuteMethod
  // - you can modify this global variable to customize the whole process
  /// TServiceFactoryServer.OnLogRestExecuteMethod 使用的选项
   // - 您可以修改此全局变量来自定义整个过程
  SERVICELOG_WRITEOPTIONS: TTextWriterWriteObjectOptions =
    [woDontStoreDefault, woDontStoreVoid, woHideSensitivePersonalInformation];


/// serialize most kind of content as JSON, using its RTTI
// - is just a wrapper around TTextWriter.AddTypedJson()
// - so would handle tkClass, tkEnumeration, tkSet, tkRecord, tkDynArray,
// tkVariant kind of content - other kinds would return 'null'
// - you can override serialization options if needed
/// 使用 RTTI 将大多数类型的内容序列化为 JSON
// - 只是 TTextWriter.AddTypedJson() 的包装
// - 因此将处理 tkClass、tkEnumeration、tkSet、tkRecord、tkDynArray、tkVariant 类型的内容 - 其他类型将返回 'null'
// - 如果需要，您可以覆盖序列化选项
procedure SaveJson(const Value; TypeInfo: PRttiInfo;
  Options: TTextWriterOptions; var result: RawUtf8); overload;

/// serialize most kind of content as JSON, using its RTTI
// - is just a wrapper around TTextWriter.AddTypedJson()
// - so would handle tkClass, tkEnumeration, tkSet, tkRecord, tkDynArray,
// tkVariant kind of content - other kinds would return 'null'
/// 使用 RTTI 将大多数类型的内容序列化为 JSON
// - 只是 TTextWriter.AddTypedJson() 的包装
// - 因此将处理 tkClass、tkEnumeration、tkSet、tkRecord、tkDynArray、tkVariant 类型的内容 - 其他类型将返回 'null'
function SaveJson(const Value; TypeInfo: PRttiInfo;
  EnumSetsAsText: boolean = false): RawUtf8; overload;
  {$ifdef HASINLINE}inline;{$endif}

/// save record into its JSON serialization as saved by TTextWriter.AddRecordJson
// - will use default Base64 encoding over RecordSave() binary - or custom true
// JSON format (as set by Rtti.RegisterFromText/TRttiJson.RegisterCustomSerializer
// or via enhanced RTTI), if available (following EnumSetsAsText optional
// parameter for nested enumerates and sets)
/// 将记录保存到 TTextWriter.AddRecordJson 保存的 JSON 序列化中
// - 将使用 RecordSave() 二进制文件的默认 Base64 编码 - 或自定义 true。 
// JSON 格式（由 Rtti.RegisterFromText/TRttiJson.RegisterCustomSerializer 设置或通过增强的 RTTI 设置），如果可用（以下为嵌套枚举和集合的 EnumSetsAsText 可选参数）
function RecordSaveJson(const Rec; TypeInfo: PRttiInfo;
  EnumSetsAsText: boolean = false): RawUtf8;
  {$ifdef HASINLINE}inline;{$endif}

/// serialize a dynamic array content as JSON
// - Value shall be set to the source dynamic array field
// - is just a wrapper around TTextWriter.AddDynArrayJson(), creating
// a temporary TDynArray wrapper on the stack
// - to be used e.g. for custom record JSON serialization, within a
// TDynArrayJsonCustomWriter callback or RegisterCustomJsonSerializerFromText()
// (following EnumSetsAsText optional parameter for nested enumerates and sets)
/// 将动态数组内容序列化为 JSON
// - 值应设置为源动态数组字段
// - 只是 TTextWriter.AddDynArrayJson() 的包装器，在堆栈上创建临时 TDynArray 包装器
// - 例如使用 对于自定义记录 JSON 序列化，在 TDynArrayJsonCustomWriter 回调或 RegisterCustomJsonSerializerFromText() 中（以下为嵌套枚举和集合的 EnumSetsAsText 可选参数）
function DynArraySaveJson(const Value; TypeInfo: PRttiInfo;
  EnumSetsAsText: boolean = false): RawUtf8;

/// serialize a dynamic array content, supplied as raw binary buffer, as JSON
// - Value shall be set to the source dynamic array field
// - is just a wrapper around TTextWriter.AddDynArrayJson(), creating
// a temporary TDynArray wrapper on the stack
// - to be used e.g. for custom record JSON serialization, within a
// TDynArrayJsonCustomWriter callback or RegisterCustomJsonSerializerFromText()
/// 序列化动态数组内容，以原始二进制缓冲区形式提供，如 JSON
// - 值应设置为源动态数组字段
// - 只是 TTextWriter.AddDynArrayJson() 的包装器，在堆栈上创建临时 TDynArray 包装器
// - 例如使用 对于自定义记录 JSON 序列化，在 TDynArrayJsonCustomWriter 回调或 RegisterCustomJsonSerializerFromText() 中
function DynArrayBlobSaveJson(TypeInfo: PRttiInfo; BlobValue: pointer): RawUtf8;

/// will serialize set of TObject into its UTF-8 JSON representation
// - follows ObjectToJson()/TTextWriter.WriterObject() functions output
// - if Names is not supplied, the corresponding class names would be used
/// 将 TObject 集合序列化为其 UTF-8 JSON 表示形式
// - 遵循 ObjectToJson()/TTextWriter.WriterObject() 函数输出
// - 如果未提供名称，则将使用相应的类名称
function ObjectsToJson(const Names: array of RawUtf8; const Values: array of TObject;
  Options: TTextWriterWriteObjectOptions = [woDontStoreDefault]): RawUtf8;

/// persist a class instance into a JSON file
// - returns TRUE on success, false on error (e.g. the file name is invalid
// or the file is existing and could not be overwritten)
// - see ObjectToJson() as defined in momrot.core.text.pas
/// 将类实例保存到 JSON 文件中
// - 成功时返回 TRUE，错误时返回 false（例如文件名无效或文件已存在且无法覆盖）
// - 请参阅 momrot.core.text.pas 中定义的 ObjectToJson()
function ObjectToJsonFile(Value: TObject; const JsonFile: TFileName;
  Options: TTextWriterWriteObjectOptions = [woHumanReadable]): boolean;

/// will serialize any TObject into its expanded UTF-8 JSON representation
// - includes debugger-friendly information, similar to TSynLog, i.e.
// class name and sets/enumerates as text
// - redirect to ObjectToJson() with the proper TTextWriterWriteObjectOptions,
// since our JSON serialization detects and serialize Exception.Message
/// 将任何 TObject 序列化为其扩展的 UTF-8 JSON 表示形式
// - 包括调试器友好的信息，类似于 TSynLog，即类名和设置/枚举为文本
// - 使用正确的 TTextWriterWriteObjectOptions 重定向到 ObjectToJson()，因为我们的 JSON 序列化检测并序列化 Exception.Message
function ObjectToJsonDebug(Value: TObject;
  Options: TTextWriterWriteObjectOptions = [woDontStoreDefault,
    woHumanReadable, woStoreClassName, woStorePointer]): RawUtf8;

/// unserialize most kind of content as JSON, using its RTTI, as saved by
// TTextWriter.AddRecordJson / RecordSaveJson
// - is just a wrapper around GetDataFromJson() global low-level function
// - returns nil on error, or the end of buffer on success
// - warning: the JSON buffer will be modified in-place during process - use
// a temporary copy if you need to access it later or if the string comes from
// a constant (refcount=-1) - see e.g. the overloaded RecordLoadJson()
/// 使用 TTextWriter.AddRecordJson / RecordSaveJson 保存的 RTTI 将大多数类型的内容反序列化为 JSON
// - 只是 GetDataFromJson() 全局低级函数的包装
// - 出错时返回 nil，成功时返回缓冲区末尾
// - 警告：JSON 缓冲区将在处理过程中就地修改 - 如果稍后需要访问它或者字符串来自常量 (refcount=-1)，请使用临时副本 - 请参阅例如 重载的 RecordLoadJson()
function LoadJson(var Value; Json: PUtf8Char; TypeInfo: PRttiInfo;
  EndOfObject: PUtf8Char = nil; CustomVariantOptions: PDocVariantOptions = nil;
  Tolerant: boolean = true): PUtf8Char;

/// fill a record content from a JSON serialization as saved by
// TTextWriter.AddRecordJson / RecordSaveJson
// - will use default Base64 encoding over RecordSave() binary - or custom
// JSON format (as set by Rtti.RegisterFromText/TRttiJson.RegisterCustomSerializer
// or via enhanced RTTI), if available
// - returns nil on error, or the end of buffer on success
// - warning: the JSON buffer will be modified in-place during process - use
// a temporary copy if you need to access it later or if the string comes from
// a constant (refcount=-1) - see e.g. the overloaded RecordLoadJson()
/// 从 TTextWriter.AddRecordJson / RecordSaveJson 保存的 JSON 序列化中填充记录内容
// - 将使用 RecordSave() 二进制的默认 Base64 编码 - 或自定义 JSON 格式（由 Rtti.RegisterFromText/TRttiJson.RegisterCustomSerializer 设置或通过增强型 RTTI 设置）（如果可用）
// - 出错时返回 nil，成功时返回缓冲区末尾
// - 警告：JSON 缓冲区将在处理过程中就地修改 - 如果稍后需要访问它或者字符串来自常量 (refcount=-1)，请使用临时副本 - 请参阅例如 重载的 RecordLoadJson()
function RecordLoadJson(var Rec; Json: PUtf8Char; TypeInfo: PRttiInfo;
  EndOfObject: PUtf8Char = nil; CustomVariantOptions: PDocVariantOptions = nil;
  Tolerant: boolean = true): PUtf8Char; overload;

/// fill a record content from a JSON serialization as saved by
// TTextWriter.AddRecordJson / RecordSaveJson
// - this overloaded function will make a private copy before parsing it,
// so is safe with a read/only or shared string - but slightly slower
// - will use default Base64 encoding over RecordSave() binary - or custom
// JSON format (as set by Rtti.RegisterFromText/TRttiJson.RegisterCustomSerializer
// or via enhanced RTTI), if available
/// 从 TTextWriter.AddRecordJson / RecordSaveJson 保存的 JSON 序列化中填充记录内容
// - 这个重载函数将在解析之前创建一个私有副本，因此对于只读或共享字符串来说是安全的 - 但速度稍慢
// - 将使用 RecordSave() 二进制的默认 Base64 编码 - 或自定义 JSON 格式（由 Rtti.RegisterFromText/TRttiJson.RegisterCustomSerializer 设置或通过增强型 RTTI 设置）（如果可用）
function RecordLoadJson(var Rec; const Json: RawUtf8; TypeInfo: PRttiInfo;
  CustomVariantOptions: PDocVariantOptions = nil;
  Tolerant: boolean = true): boolean; overload;

/// fill a dynamic array content from a JSON serialization as saved by
// TTextWriter.AddDynArrayJson
// - Value shall be set to the target dynamic array field
// - is just a wrapper around TDynArray.LoadFromJson(), creating a temporary
// TDynArray wrapper on the stack
// - return a pointer at the end of the data read from JSON, nil in case
// of an invalid input buffer
// - to be used e.g. for custom record JSON unserialization, within a
// TDynArrayJsonCustomReader callback
// - warning: the JSON buffer will be modified in-place during process - use
// a temporary copy if you need to access it later or if the string comes from
// a constant (refcount=-1) - see e.g. the overloaded DynArrayLoadJson()
/// 从 TTextWriter.AddDynArrayJson 保存的 JSON 序列化中填充动态数组内容
// - 值应设置为目标动态数组字段
// - 只是 TDynArray.LoadFromJson() 的包装器，在堆栈上创建临时 TDynArray 包装器
// - 在从 JSON 读取的数据末尾返回一个指针，如果输入缓冲区无效，则返回 nil
// - 例如使用 对于自定义记录 JSON 反序列化，在 TDynArrayJsonCustomReader 回调中
// - 警告：JSON 缓冲区将在处理过程中就地修改 - 如果稍后需要访问它或者字符串来自常量 (refcount=-1)，请使用临时副本 - 请参阅例如 重载的 DynArrayLoadJson()
function DynArrayLoadJson(var Value; Json: PUtf8Char; TypeInfo: PRttiInfo;
  EndOfObject: PUtf8Char = nil; CustomVariantOptions: PDocVariantOptions = nil;
  Tolerant: boolean = true): PUtf8Char; overload;

/// fill a dynamic array content from a JSON serialization as saved by
// TTextWriter.AddDynArrayJson, which won't be modified
// - this overloaded function will make a private copy before parsing it,
// so is safe with a read/only or shared string - but slightly slower
/// 从 TTextWriter.AddDynArrayJson 保存的 JSON 序列化中填充动态数组内容，该内容不会被修改
// - 这个重载函数将在解析之前创建一个私有副本，因此对于只读或共享字符串来说是安全的 - 但速度稍慢
function DynArrayLoadJson(var Value; const Json: RawUtf8;
  TypeInfo: PRttiInfo; CustomVariantOptions: PDocVariantOptions = nil;
  Tolerant: boolean = true): boolean; overload;

/// read an object properties, as saved by ObjectToJson function
// - ObjectInstance must be an existing TObject instance
// - the data inside From^ is modified in-place (unescaped and transformed):
// calling JsonToObject(pointer(JSONRawUtf8)) will change the JSONRawUtf8
// variable content, which may not be what you expect - consider using the
// ObjectLoadJson() function instead
// - handle integer, Int64, enumerate (including boolean), set, floating point,
// TDateTime, TCollection, TStrings, TRawUtf8List, variant, and string properties
// (excluding ShortString, but including WideString and UnicodeString under
// Delphi 2009+)
// - TList won't be handled since it may leak memory when calling TList.Clear
// - won't handle TObjectList (even if ObjectToJson is able to serialize
// them) since has no way of knowing the object type to add (TCollection.Add
// is missing), unless: 1. you set the TObjectListItemClass property as expected,
// and provide a TObjectList object, or 2. woStoreClassName option has been
// used at ObjectToJson() call and the corresponding classes have been previously
// registered by Rtti.RegisterClass()
// - will clear any previous TCollection objects, and convert any null JSON
// basic type into nil - e.g. if From='null', will call FreeAndNil(Value)
// - you can add some custom (un)serializers for ANY class, via mormot.core.json
// TRttiJson.RegisterCustomSerializer() class method
// - set Valid=TRUE on success, Valid=FALSE on error, and the main function
// will point in From at the syntax error place (e.g. on any unknown property name)
// - caller should explicitly perform a SetDefaultValuesObject(Value) if
// the default values are expected to be set before JSON parsing
/// 读取由ObjectToJson函数保存的对象属性
// - ObjectInstance 必须是现有的 TObject 实例
// - From^ 中的数据就地修改（未转义和转换）：调用 JsonToObject(pointer(JSONRawUtf8)) 将更改 JSONRawUtf8 变量内容，这可能不是您所期望的 - 考虑使用 ObjectLoadJson() 函数
// - 处理整数、Int64、枚举（包括布尔值）、集合、浮点、TDateTime、TCollection、TStrings、TRawUtf8List、变体和字符串属性（不包括 ShortString，但包括 Delphi 2009+ 下的 WideString 和 UnicodeString）
// - TList 将不会被处理，因为它在调用 TList.Clear 时可能会泄漏内存
// - 不会处理 TObjectList（即使 ObjectToJson 能够序列化它们），因为无法知道要添加的对象类型（缺少 TCollection.Add），除非： 1. 按预期设置 TObjectListItemClass 属性，并且 提供 TObjectList 对象，或 2. 在 ObjectToJson() 调用中使用了 woStoreClassName 选项，并且相应的类已预先通过 Rtti.RegisterClass() 注册
// - 将清除任何先前的 TCollection 对象，并将任何 null JSON 基本类型转换为 nil - 例如 如果 From='null'，将调用 FreeAndNil(Value)
// - 您可以通过 mormot.core.json TRttiJson.RegisterCustomSerializer() 类方法为任何类添加一些自定义（非）序列化器
// - 成功时设置 Valid=TRUE，错误时设置 Valid=FALSE，主函数将指向语法错误位置的 From（例如，在任何未知的属性名称上）
// - 如果希望在 JSON 解析之前设置默认值，则调用者应显式执行 SetDefaultValuesObject(Value)
function JsonToObject(var ObjectInstance; From: PUtf8Char;
  out Valid: boolean; TObjectListItemClass: TClass = nil;
  Options: TJsonParserOptions = []): PUtf8Char;

/// parse the supplied JSON with some tolerance about Settings format
// - will make a TSynTempBuffer copy for parsing, and un-comment it
// - returns true if the supplied JSON was successfully retrieved
// - returns false and set InitialJsonContent := '' on error
/// 解析提供的 JSON，对设置格式有一定的容忍度
// - 将创建一个 TSynTempBuffer 副本用于解析，并取消注释
// - 如果成功检索到提供的 JSON，则返回 true
// - 出错时返回 false 并设置 InitialJsonContent := ''
function JsonSettingsToObject(var InitialJsonContent: RawUtf8;
  Instance: TObject): boolean;

/// read an object properties, as saved by ObjectToJson function
// - ObjectInstance must be an existing TObject instance
// - this overloaded version will make a private copy of the supplied JSON
// content (via TSynTempBuffer), to ensure the original buffer won't be modified
// during process, before calling safely JsonToObject()
// - will return TRUE on success, or FALSE if the supplied JSON was invalid
/// 读取由ObjectToJson函数保存的对象属性
// - ObjectInstance 必须是现有的 TObject 实例
// - 此重载版本将生成所提供 JSON 内容的私有副本（通过 TSynTempBuffer），以确保在安全调用 JsonToObject() 之前原始缓冲区不会在处理过程中被修改
// - 如果成功则返回 TRUE，如果提供的 JSON 无效则返回 FALSE
function ObjectLoadJson(var ObjectInstance; const Json: RawUtf8;
  TObjectListItemClass: TClass = nil;
  Options: TJsonParserOptions = []): boolean;

/// create a new object instance, as saved by ObjectToJson(...,[...,woStoreClassName,...]);
// - JSON input should be either 'null', either '{"ClassName":"TMyClass",...}'
// - woStoreClassName option shall have been used at ObjectToJson() call
// - and the corresponding class shall have been previously registered by
// Rtti.RegisterClass() to retrieve the class type from it name
// - the data inside From^ is modified in-place (unescaped and transformed):
// don't call JsonToObject(pointer(JSONRawUtf8)) but makes a temporary copy of
// the JSON text buffer before calling this function, if want to reuse it later
/// 创建一个新的对象实例，由 ObjectToJson(...,[...,woStoreClassName,...]); 保存
// - JSON 输入应该是 'null' 或 '{"ClassName":"TMyClass",...}'
// - woStoreClassName 选项应在 ObjectToJson() 调用中使用
// - 相应的类之前应已由 Rtti.RegisterClass() 注册以从其名称中检索类类型
// - From^ 中的数据被就地修改（未转义和转换）：不要调用 JsonToObject(pointer(JSONRawUtf8)) 但在调用此函数之前创建 JSON 文本缓冲区的临时副本（如果想重用它） 之后
function JsonToNewObject(var From: PUtf8Char; var Valid: boolean;
  Options: TJsonParserOptions = []): TObject;

/// read an TObject published property, as saved by ObjectToJson() function
// - will use direct in-memory reference to the object, or call the corresponding
// setter method (if any), creating a temporary instance
// - unserialize the JSON input buffer via a call to JsonToObject()
// - by default, a temporary instance will be created if a published field
// has a setter, and the instance is expected to be released later by the
// owner class: you can set the j2oSetterExpectsToFreeTempInstance option
// to let this method release it when the setter returns
/// 读取 TObject 发布的属性，由 ObjectToJson() 函数保存
// - 将使用对对象的直接内存引用，或调用相应的setter方法（如果有），创建一个临时实例
// - 通过调用 JsonToObject() 反序列化 JSON 输入缓冲区
// - 默认情况下，如果已发布的字段有setter，则会创建一个临时实例，并且该实例预计稍后由所有者类释放：您可以设置j2oSetterExpectsToFreeTempInstance选项，让该方法在setter返回时释放它
function PropertyFromJson(Prop: PRttiCustomProp; Instance: TObject;
  From: PUtf8Char; var Valid: boolean;
  Options: TJsonParserOptions = []): PUtf8Char;

/// decode a specified parameter compatible with URI encoding into its original
// object contents
// - ObjectInstance must be an existing TObject instance
// - will call internally JsonToObject() function to unserialize its content
// - UrlDecodeExtended('price=20.45&where=LastName%3D%27M%C3%B4net%27','PRICE=',P,@Next)
// will return Next^='where=...' and P=20.45
// - if Upper is not found, Value is not modified, and result is FALSE
// - if Upper is found, Value is modified with the supplied content, and result is TRUE
/// 将兼容URI编码的指定参数解码为其原始对象内容
// - ObjectInstance 必须是现有的 TObject 实例
// - 将调用内部 JsonToObject() 函数来反序列化其内容
// - UrlDecodeExtended('price=20.45&where=LastName%3D%27M%C3%B4net%27','PRICE=',P,@Next) 将返回 Next^='where=...' 和 P=20.45
// - 如果未找到 Upper，则不修改 Value，结果为 FALSE
// - 如果找到 Upper，则使用提供的内容修改 Value，结果为 TRUE
function UrlDecodeObject(U: PUtf8Char; Upper: PAnsiChar;
  var ObjectInstance; Next: PPUtf8Char = nil;
  Options: TJsonParserOptions = []): boolean;

/// fill the object properties from a JSON file content
// - ObjectInstance must be an existing TObject instance
// - this function will call RemoveCommentsFromJson() before process
/// 从JSON文件内容填充对象属性
// - ObjectInstance 必须是现有的 TObject 实例
// - 该函数将在处理之前调用RemoveCommentsFromJson()
function JsonFileToObject(const JsonFile: TFileName; var ObjectInstance;
  TObjectListItemClass: TClass = nil;
  Options: TJsonParserOptions = []): boolean;


const
  /// standard header for an UTF-8 encoded XML file
  /// UTF-8 编码的 XML 文件的标准标头
  XMLUTF8_HEADER = '<?xml version="1.0" encoding="UTF-8"?>'#13#10;

  /// standard namespace for a generic XML File
  /// 通用 XML 文件的标准命名空间
  XMLUTF8_NAMESPACE = '<contents xmlns="http://www.w3.org/2001/XMLSchema-instance">';

/// convert a JSON array or document into a simple XML content
// - just a wrapper around TTextWriter.AddJsonToXML, with an optional
// header before the XML converted data (e.g. XMLUTF8_HEADER), and an optional
// name space content node which will nest the generated XML data (e.g.
// '<contents xmlns="http://www.w3.org/2001/XMLSchema-instance">') - the
// corresponding ending token will be appended after (e.g. '</contents>')
// - WARNING: the JSON buffer is decoded in-place, so P^ WILL BE modified
/// 将 JSON 数组或文档转换为简单的 XML 内容
// - 只是 TTextWriter.AddJsonToXML 的包装，在 XML 转换数据之前有一个可选的标头（例如 XMLUTF8_HEADER），以及一个可选的名称空间内容节点，它将嵌套生成的 XML 数据（例如 '<contents xmlns="http:/ /www.w3.org/2001/XMLSchema-instance">') - 相应的结束标记将附加在后面（例如 '</contents>'）
// - 警告：JSON 缓冲区已就地解码，因此 P^ 将被修改
procedure JsonBufferToXML(P: PUtf8Char; const Header, NameSpace: RawUtf8;
  out result: RawUtf8);

/// convert a JSON array or document into a simple XML content
// - just a wrapper around TTextWriter.AddJsonToXML, making a private copy
// of the supplied JSON buffer using TSynTempBuffer (so that JSON content
// would stay untouched)
// - the optional header is added at the beginning of the resulting string
// - an optional name space content node could be added around the generated XML,
// e.g. '<content>'
/// 将 JSON 数组或文档转换为简单的 XML 内容
// - 只是 TTextWriter.AddJsonToXML 的包装，使用 TSynTempBuffer 制作提供的 JSON 缓冲区的私有副本（以便 JSON 内容保持不变）
// - 可选标头添加到结果字符串的开头
// - 可以在生成的 XML 周围添加可选的名称空间内容节点，例如 '<内容>'
function JsonToXML(const Json: RawUtf8; const Header: RawUtf8 = XMLUTF8_HEADER;
  const NameSpace: RawUtf8 = ''): RawUtf8;


{ ********************* Abstract Classes with Auto-Create-Fields }
{ ********************* 具有自动创建字段的抽象类 }

/// should be called by T*AutoCreateFields constructors
// - will also register this class type, if needed, so RegisterClass() is
// redundant to this method
/// 应由 T*AutoCreateFields 构造函数调用
// - 如果需要的话，还将注册此类类型，因此 RegisterClass() 对于此方法来说是多余的
procedure AutoCreateFields(ObjectInstance: TObject);
  {$ifdef HASINLINE}inline;{$endif}

/// should be called by T*AutoCreateFields destructors
// - constructor should have called AutoCreateFields()
/// 应由 T*AutoCreateFields 析构函数调用
// - 构造函数应该调用 AutoCreateFields()
procedure AutoDestroyFields(ObjectInstance: TObject);
  {$ifdef HASINLINE}inline;{$endif}

/// internal function called by AutoCreateFields() when inlined
// - do not call this internal function, but always AutoCreateFields()
/// 内联时由 AutoCreateFields() 调用的内部函数
// - 不要调用此内部函数，但始终调用 AutoCreateFields()
function DoRegisterAutoCreateFields(ObjectInstance: TObject): TRttiJson;


type
  /// abstract TPersistent class, which will instantiate all its nested TPersistent
  // class published properties, then release them (and any T*ObjArray) when freed
  // - TSynAutoCreateFields is to be preferred in most cases, thanks to its
  // lower overhead
  // - note that non published (e.g. public) properties won't be instantiated,
  // serialized, nor released - but may contain weak references to other classes
  // - please take care that you will not create any endless recursion: you should
  // ensure that at one level, nested published properties won't have any class
  // instance refering to its owner (there is no weak reference - remember!)
  // - since the destructor will release all nested properties, you should
  // never store a reference to any of those nested instances if this owner
  // may be freed before
  /// 抽象 TPersistent 类，它将实例化所有嵌套的 TPersistent 类发布的属性，然后在释放时释放它们（以及任何 T*ObjArray）
   // - TSynAutoCreateFields 在大多数情况下是首选，因为它的开销较低
   // - 请注意，非发布（例如公共）属性不会被实例化、序列化或发布 - 但可能包含对其他类的弱引用
   // - 请注意不要创建任何无休止的递归：您应该确保在某一级别，嵌套的已发布属性不会有任何类实例引用其所有者（没有弱引用 - 请记住！）
   // - 由于析构函数将释放所有嵌套属性，因此如果此所有者之前可能被释放，则永远不应该存储对任何这些嵌套实例的引用  
  TPersistentAutoCreateFields = class(TPersistentWithCustomCreate)
  public
    /// this overriden constructor will instantiate all its nested
    // TPersistent/TSynPersistent/TSynAutoCreateFields published properties
    /// 这个重写的构造函数将实例化其所有嵌套
     // TPercient/TSynPercient/TSynAutoCreateFields 已发布属性    
    constructor Create; override;
    /// finalize the instance, and release its published properties
    /// 完成实例，并释放其已发布的属性
    destructor Destroy; override;
  end;

  /// our own empowered TPersistentAutoCreateFields-like parent class
  // - this class is a perfect parent to store any data by value, e.g. DDD Value
  // Objects, Entities or Aggregates
  // - is defined as an abstract class able with a virtual constructor, RTTI
  // for published properties, and automatic memory management of all nested
  // class published properties: any class defined as a published property will
  // be owned by this instance - i.e. with strong reference
  // - will also release any T*ObjArray dynamic array storage of persistents,
  // previously registered via Rtti.RegisterObjArray() for Delphi 7-2009
  // - nested published classes (or T*ObjArray) don't need to inherit from
  // TSynAutoCreateFields: they may be from any TPersistent/TSynPersistent type
  // - note that non published (e.g. public) properties won't be instantiated,
  // serialized, nor released - but may contain weak references to other classes
  // - please take care that you will not create any endless recursion: you should
  // ensure that at one level, nested published properties won't have any class
  // instance refering to its owner (there is no weak reference - remember!)
  // - since the destructor will release all nested properties, you should
  // never store a reference to any of those nested instances if this owner
  // may be freed before
  // - TPersistent/TPersistentAutoCreateFields have an unexpected speed overhead
  // due a giant lock introduced to manage property name fixup resolution
  // (which we won't use outside the VCL) - this class is definitively faster
  /// 我们自己的类似 TPersistentAutoCreateFields 的父类
   // - 这个类是一个完美的父类，可以按值存储任何数据，例如 DDD 值对象、实体或聚合
   // - 被定义为能够使用虚拟构造函数 RTTI 的抽象类
   // 对于已发布的属性，以及所有嵌套类已发布属性的自动内存管理：定义为已发布属性的任何类都将归此实例所有 - 即具有强引用
   // - 还将释放任何持久性的 T*ObjArray 动态数组存储，之前通过 Rtti.RegisterObjArray() 为 Delphi 7-2009 注册
   // - 嵌套的已发布类（或 T*ObjArray）不需要从 TSynAutoCreateFields 继承：它们可以来自任何 TPercient/TSynPercient 类型
   // - 请注意，非发布（例如公共）属性不会被实例化、序列化或发布 - 但可能包含对其他类的弱引用
   // - 请注意不要创建任何无休止的递归：您应该确保在某一级别，嵌套的已发布属性不会有任何类实例引用其所有者（没有弱引用 - 请记住！）
   // - 由于析构函数将释放所有嵌套属性，因此如果此所有者之前可能被释放，则永远不应该存储对任何这些嵌套实例的引用
   // - 由于引入了一个巨大的锁来管理属性名称修复解析（我们不会在 VCL 之外使用），因此 TPercient/TPercientAutoCreateFields 具有意外的速度开销 - 这个类绝对更快  
  TSynAutoCreateFields = class(TSynPersistent)
  public
    /// this overriden constructor will instantiate all its nested
    // TPersistent/TSynPersistent/TSynAutoCreateFields published properties
    /// 这个重写的构造函数将实例化其所有嵌套
     // TPercient/TSynPercient/TSynAutoCreateFields 已发布属性
    constructor Create; override;
    /// finalize the instance, and release its published properties
    /// 完成实例，并释放其已发布的属性
    destructor Destroy; override;
  end;

  /// adding locking methods to a TSynAutoCreateFields with virtual constructor
  /// 使用虚拟构造函数向 TSynAutoCreateFields 添加锁定方法
  TSynAutoCreateFieldsLocked = class(TSynPersistentLock)
  public
    /// initialize the object instance, and its associated lock
    /// 初始化对象实例及其关联的锁
    constructor Create; override;
    /// release the instance (including the locking resource)
    /// 释放实例（包括锁定资源）
    destructor Destroy; override;
  end;

  /// abstract TInterfacedObject class, which will instantiate all its nested
  // TPersistent/TSynPersistent published properties, then release them when freed
  // - will handle automatic memory management of all nested class and T*ObjArray
  // published properties: any class or T*ObjArray defined as a published
  // property will be owned by this instance - i.e. with strong reference
  // - non published properties (e.g. public) won't be instantiated, so may
  // store weak class references
  // - could be used for gathering of TCollectionItem properties, e.g. for
  // Domain objects in DDD, especially for list of value objects, with some
  // additional methods defined by an Interface
  // - since the destructor will release all nested properties, you should
  // never store a reference to any of those nested instances if this owner
  // may be freed before
  /// 抽象TInterfacedObject类，它将实例化其所有嵌套
   // TPercient/TSynPercient 发布的属性，然后在释放时释放它们
   // - 将处理所有嵌套类和 T*ObjArray 已发布属性的自动内存管理：定义为已发布属性的任何类或 T*ObjArray 将归此实例所有 - 即具有强引用
   // - 非发布属性（例如公共）不会被实例化，因此可能存储弱类引用
   // - 可用于收集 TCollectionItem 属性，例如 对于 DDD 中的域对象，尤其是值对象列表，以及由接口定义的一些附加方法
   // - 由于析构函数将释放所有嵌套属性，因此如果此所有者之前可能被释放，则永远不应该存储对任何这些嵌套实例的引用
  TInterfacedObjectAutoCreateFields = class(TInterfacedObjectWithCustomCreate)
  public
    /// this overriden constructor will instantiate all its nested
    // TPersistent/TSynPersistent/TSynAutoCreateFields class and T*ObjArray
    // published properties
    /// 这个重写的构造函数将实例化其所有嵌套
     // TPercient/TSynPercient/TSynAutoCreateFields 类和 T*ObjArray
     // 发布的属性
    constructor Create; override;
    /// finalize the instance, and release its published properties
    /// 完成实例，并释放其已发布的属性
    destructor Destroy; override;
  end;

  /// abstract TCollectionItem class, which will instantiate all its nested class
  // published properties, then release them (and any T*ObjArray) when freed
  // - could be used for gathering of TCollectionItem properties, e.g. for
  // Domain objects in DDD, especially for list of value objects
  // - consider using T*ObjArray dynamic array published properties in your
  // value types instead of TCollection storage: T*ObjArray have a lower overhead
  // and are easier to work with, once Rtti.RegisterObjArray is called on Delphi
  // 7-2009 to register the T*ObjArray type (not needed on FPC and Delphi 2010+)
  // - note that non published (e.g. public) properties won't be instantiated,
  // serialized, nor released - but may contain weak references to other classes
  // - please take care that you will not create any endless recursion: you should
  // ensure that at one level, nested published properties won't have any class
  // instance refering to its owner (there is no weak reference - remember!)
  // - since the destructor will release all nested properties, you should
  // never store a reference to any of those nested instances if this owner
  // may be freed before
  /// 抽象 TCollectionItem 类，它将实例化其所有嵌套类发布的属性，然后在释放时释放它们（以及任何 T*ObjArray）
   // - 可用于收集 TCollectionItem 属性，例如 对于 DDD 中的域对象，尤其是值对象列表
   // - 考虑在值类型中使用 T*ObjArray 动态数组发布属性而不是 TCollection 存储：一旦在 Delphi 7-2009 上调用 Rtti.RegisterObjArray 来注册 T，T*ObjArray 的开销较低并且更易于使用 *ObjArray 类型（FPC 和 Delphi 2010+ 上不需要）
   // - 请注意，非发布（例如公共）属性不会被实例化、序列化或发布 - 但可能包含对其他类的弱引用
   // - 请注意不要创建任何无休止的递归：您应该确保在某一级别，嵌套的已发布属性不会有任何类实例引用其所有者（没有弱引用 - 请记住！）
   // - 由于析构函数将释放所有嵌套属性，因此如果此所有者之前可能被释放，则永远不应该存储对任何这些嵌套实例的引用  
  TCollectionItemAutoCreateFields = class(TCollectionItem)
  public
    /// this overriden constructor will instantiate all its nested
    // TPersistent/TSynPersistent/TSynAutoCreateFields published properties
    /// 这个重写的构造函数将实例化其所有嵌套
     // TPercient/TSynPercient/TSynAutoCreateFields 已发布属性
    constructor Create(Collection: TCollection); override;
    /// finalize the instance, and release its published properties
    /// 完成实例，并释放其已发布的属性
    destructor Destroy; override;
  end;

  /// abstract parent class able to store settings as JSON file
  /// 抽象父类能够将设置存储为 JSON 文件
  TSynJsonFileSettings = class(TSynAutoCreateFields)
  protected
    fInitialJsonContent: RawUtf8;
    fFileName: TFileName;
  public
    /// read existing settings from a JSON content
    /// 从 JSON 内容中读取现有设置
    function LoadFromJson(var aJson: RawUtf8): boolean;
    /// read existing settings from a JSON file
    /// 从 JSON 文件读取现有设置
    function LoadFromFile(const aFileName: TFileName): boolean; virtual;
    /// persist the settings as a JSON file, named from LoadFromFile() parameter
    /// 将设置保存为 JSON 文件，由 LoadFromFile() 参数命名
    procedure SaveIfNeeded; virtual;
    /// optional persistence file name, as set by LoadFromFile()
    /// 可选的持久性文件名，由 LoadFromFile() 设置
    property FileName: TFileName
      read fFileName;
  end;


implementation

uses
  mormot.core.variants;


{ ********** Low-Level JSON Processing Functions }
{ ********** 低级 JSON 处理函数 }

function NeedsJsonEscape(P: PUtf8Char; PLen: integer): boolean;
var
  tab: PByteArray;
begin
  result := true;
  tab := @JSON_ESCAPE;
  if PLen > 0 then
    repeat
      if tab[ord(P^)] <> JSON_ESCAPE_NONE then
        exit;
      inc(P);
      dec(PLen);
    until PLen = 0;
  result := false;
end;

function NeedsJsonEscape(const Text: RawUtf8): boolean;
begin
  result := NeedsJsonEscape(pointer(Text), length(Text));
end;

function NeedsJsonEscape(P: PUtf8Char): boolean;
var
  tab: PByteArray;
  esc: byte;
begin
  result := false;
  if P = nil then
    exit;
  tab := @JSON_ESCAPE;
  repeat
    esc := tab[ord(P^)];
    if esc = JSON_ESCAPE_NONE then
      inc(P)
    else if esc = JSON_ESCAPE_ENDINGZERO then
      exit
    else
      break;
  until false;
  result := true;
end;

function JsonEscapeToUtf8(var D: PUtf8Char;  P: PUtf8Char): PUtf8Char;
var
  c, s: cardinal;
begin
  // P^ points at 'u1234' just after \u0123
  c := (ConvertHexToBin[ord(P[1])] shl 12) or
       (ConvertHexToBin[ord(P[2])] shl 8) or
       (ConvertHexToBin[ord(P[3])] shl 4) or
        ConvertHexToBin[ord(P[4])];
  if c = 0 then
    D^ := '?' // \u0000 is an invalid value
  else if c <= $7f then
    D^ := AnsiChar(c)
  else if c < $7ff then
  begin
    D[0] := AnsiChar($C0 or (c shr 6));
    D[1] := AnsiChar($80 or (c and $3F));
    inc(D);
  end
  else if (c >= UTF16_HISURROGATE_MIN) and
          (c <= UTF16_LOSURROGATE_MAX) then
    if PWord(P + 5)^ = ord('\') + ord('u') shl 8 then
    begin
      s := (ConvertHexToBin[ord(P[7])] shl 12)+
           (ConvertHexToBin[ord(P[8])] shl 8)+
           (ConvertHexToBin[ord(P[9])] shl 4)+
            ConvertHexToBin[ord(P[10])];
      case c of // inlined Utf16CharToUtf8()
        UTF16_HISURROGATE_MIN..UTF16_HISURROGATE_MAX:
          c := ((c - $D7C0) shl 10) or (s xor UTF16_LOSURROGATE_MIN);
        UTF16_LOSURROGATE_MIN..UTF16_LOSURROGATE_MAX:
          c := ((s - $D7C0)shl 10) or (c xor UTF16_LOSURROGATE_MIN);
      end;
      inc(D, Ucs4ToUtf8(c, D));
      result := P + 11;
      exit;
    end
    else
      D^ := '?'
  else
  begin
    D[0] := AnsiChar($E0 or (c shr 12));
    D[1] := AnsiChar($80 or ((c shr 6) and $3F));
    D[2] := AnsiChar($80 or (c and $3F));
    inc(D,2);
  end;
  inc(D);
  result := P + 5;
end;

function IsString(P: PUtf8Char): boolean;  // test if P^ is a "string" value （测试 P^ 是否是“字符串”值）
begin
  if P = nil then
  begin
    result := false;
    exit;
  end;
  while (P^ <= ' ') and
        (P^ <> #0) do
    inc(P);
  if (P[0] in ['0'..'9']) or // is first char numeric? （第一个字符是数字吗？）
     ((P[0] in ['-', '+']) and
      (P[1] in ['0'..'9'])) then
  begin
    // check if P^ is a true numerical value
    repeat
      inc(P);
    until not (P^ in ['0'..'9']); // check digits （校验位）
    if P^ = '.' then
      repeat
        inc(P);
      until not (P^ in ['0'..'9']); // check fractional digits （检查小数位）
    if ((P^ = 'e') or
        (P^ = 'E')) and
       (P[1] in ['0'..'9', '+', '-']) then
    begin
      inc(P);
      if P^ = '+' then
        inc(P)
      else if P^ = '-' then
        inc(P);
      while (P^ >= '0') and
            (P^ <= '9') do
        inc(P);
    end;
    while (P^ <= ' ') and
          (P^ <> #0) do
      inc(P);
    result := (P^ <> #0);
    exit;
  end
  else
    result := true; // don't begin with a numerical value -> must be a string （不以数值开头 -> 必须是字符串）
end;

function IsStringJson(P: PUtf8Char): boolean;  // test if P^ is a "string" value （测试 P^ 是否是“字符串”值）
var
  c4: integer;
  c: AnsiChar;
  tab: PJsonCharSet;
begin
  if P = nil then
  begin
    result := false;
    exit;
  end;
  while (P^ <= ' ') and
        (P^ <> #0) do
    inc(P);
  tab := @JSON_CHARS;
  c4 := PInteger(P)^;
  if (((c4 = NULL_LOW) or
       (c4 = TRUE_LOW)) and
      (jcEndOfJsonValueField in tab[P[4]])) or
     ((c4 = FALSE_LOW) and
      (P[4] = 'e') and
      (jcEndOfJsonValueField in tab[P[5]])) then
  begin
    result := false; // constants are no string (常量不是字符串)
    exit;
  end;
  c := P^;
  if (jcDigitFirstChar in tab[c]) and
     (((c >= '1') and (c <= '9')) or // is first char numeric? （第一个字符是数字吗？）
     ((c = '0') and ((P[1] < '0') or
                     (P[1] > '9'))) or // '012' excluded by JSON （JSON 排除了“012”）
     ((c = '-') and (P[1] >= '0') and (P[1] <= '9'))) then
  begin
    // check if c is a true numerical value （检查 c 是否为真实数值）
    repeat
      inc(P);
    until (P^ < '0') or
          (P^ > '9'); // check digits （校验位）
    if P^ = '.' then
      repeat
        inc(P);
      until (P^ < '0') or
            (P^ > '9'); // check fractional digits (检查小数位)
    if ((P^ = 'e') or
        (P^ = 'E')) and
       (jcDigitFirstChar in tab[P[1]]) then
    begin
      inc(P);
      c := P^;
      if c = '+' then
        inc(P)
      else if c = '-' then
        inc(P);
      while (P^ >= '0') and
            (P^ <= '9') do
        inc(P);
    end;
    while (P^ <= ' ') and
          (P^ <> #0) do
      inc(P);
    result := (P^ <> #0);
    exit;
  end
  else
    result := true; // don't begin with a numerical value -> must be a string （不以数值开头 -> 必须是字符串）
end;

function IsValidJson(const s: RawUtf8): boolean;
begin
  result := IsValidJson(pointer(s), length(s));
end;

function IsValidJson(P: PUtf8Char; len: PtrInt): boolean;
var
  B: PUtf8Char;
begin
  result := false;
  if (P = nil) or
     (len <= 0) or
     // ensure there is no unexpected/unsupported #0 in the middle of input (确保输入中间没有意外/不支持的 #0)
     (StrLen(P) <> len) then
    exit;
  B := P;
  P :=  GotoEndJsonItemStrict(B);
  result := (P <> nil) and
            (P - B = len);
end;

function IsValidJsonBuffer(P: PUtf8Char): boolean;
begin
  result := (P <> nil) and
            (GotoEndJsonItemStrict(P) <> nil);
end;

procedure IgnoreComma(var P: PUtf8Char);
begin
  if P <> nil then
  begin
    while (P^ <= ' ') and
          (P^ <> #0) do
      inc(P);
    if P^ = ',' then
      inc(P);
  end;
end;

function JsonPropNameValid(P: PUtf8Char): boolean;
var
  tab: PJsonCharSet;
begin
  tab := @JSON_CHARS;
  if (P <> nil) and
     (jcJsonIdentifierFirstChar in tab[P^]) then
  begin
    // ['_', '0'..'9', 'a'..'z', 'A'..'Z', '$']
    repeat
      inc(P);
    until not (jcJsonIdentifier in tab[P^]);
    // not ['_', '0'..'9', 'a'..'z', 'A'..'Z', '.', '[', ']']
    result := P^ = #0;
  end
  else
    result := false;
end;

function GetJsonField(P: PUtf8Char; out PDest: PUtf8Char; WasString: PBoolean;
  EndOfObject: PUtf8Char; Len: PInteger): PUtf8Char;
var
  D: PUtf8Char;
  c4, surrogate, extra: PtrUInt;
  c: AnsiChar;
  {$ifdef CPUX86NOTPIC}
  tab: TJsonCharSet absolute JSON_CHARS; // not enough registers (寄存器不足)
  {$else}
  tab: PJsonCharSet;
  {$endif CPUX86NOTPIC}
label
  lit;
begin
  // see http://www.ietf.org/rfc/rfc4627.txt
  if WasString <> nil then
    // not a string by default (默认情况下不是字符串)
    WasString^ := false;
  if Len <> nil then
    // ensure returns Len=0 on invalid input (PDest=nil) (确保在无效输入时返回 Len=0 (PDest=nil))
    Len^ := 0;
  PDest := nil; // PDest=nil indicates error or unexpected end (#0) (PDest=nil 表示错误或意外结束 (#0))
  result := nil;
  if P = nil then
    exit;
  while P^ <= ' ' do
  begin
    if P^ = #0 then
      exit;
    inc(P);
  end;
  {$ifndef CPUX86NOTPIC}
  tab := @JSON_CHARS;
  {$endif CPUX86NOTPIC}
  case JSON_TOKENS[P^] of
    jtFirstDigit: // '-', '0'..'9'
      begin
        // numerical value
        result := P;
        if P^ = '0' then
          if (P[1] >= '0') and
             (P[1] <= '9') then
            // 0123 excluded by JSON!
            exit;
        repeat // loop all '-', '+', '0'..'9', '.', 'E', 'e'
          inc(P);
        until not (jcDigitFloatChar in tab[P^]);
        if P^ = #0 then
          exit; // a JSON number value should be followed by , } or ]
        if Len <> nil then
          Len^ := P - result;
        if P^ <= ' ' then
        begin
          P^ := #0; // force numerical field with no trailing ' '  (强制不带尾随“ ”的数值字段)
          inc(P);
        end;
      end;
    jtDoubleQuote: // '"'
      begin
        // " -> unescape P^ into D^
       inc(P);
       result := P; // result points to the unescaped JSON string
        if WasString <> nil then
          WasString^ := true;
        while not (jcJsonStringMarker in tab[P^]) do
          // not [#0, '"', '\']
          inc(P); // very fast parsing of most UTF-8 chars within "string"
        D := P;
        if P^ <> '"' then
        repeat
          // escape needed -> in-place unescape from P^ into D^
          c := P^;
          if not (jcJsonStringMarker in tab[c]) then
          begin
lit:        inc(P);
            D^ := c;
            inc(D);
            continue; // very fast parsing of most UTF-8 chars within "string"
          end;
          // P^ is either #0, '"' or '\'
          if c = '"' then
            // end of string
            break;
          if c = #0 then
            // premature ending (PDest=nil)
            exit;
          // unescape JSON text: get char after \
          inc(P); // P^ was '\' here
          c := P^;
          if (c = '"') or
             (c = '\') then
            // most common cases are \\ or \"
            goto lit
          else if c = #0 then
            // to avoid potential buffer overflow issue on \#0
            exit
          else if c = 'b' then
            c := #8
          else if c = 't' then
            c := #9
          else if c = 'n' then
            c := #10
          else if c = 'f' then
            c := #12
          else if c = 'r' then
            c := #13
          else if c = 'u' then
          begin
            // decode '\u0123' UTF-16 into UTF-8
            // note: JsonEscapeToUtf8() inlined here to optimize GetJsonField
            c4 := (ConvertHexToBin[ord(P[1])] shl 12) or
                  (ConvertHexToBin[ord(P[2])] shl 8) or
                  (ConvertHexToBin[ord(P[3])] shl 4) or
                   ConvertHexToBin[ord(P[4])];
            inc(P, 5); // optimistic conversion (no check)
            case c4 of
              0:
                begin
                  // \u0000 is an invalid value (at least in our framework)
                  D^ := '?';
                  inc(D);
                end;
              1..$7f:
                begin
                  D^ := AnsiChar(c4);
                  inc(D);
                end;
              $80..$7ff:
                begin
                  D[0] := AnsiChar($C0 or (c4 shr 6));
                  D[1] := AnsiChar($80 or (c4 and $3F));
                  inc(D, 2);
                end;
              UTF16_HISURROGATE_MIN..UTF16_LOSURROGATE_MAX:
                if PWord(P)^ = ord('\') + ord('u') shl 8 then
                begin
                  inc(P);
                  surrogate := (ConvertHexToBin[ord(P[1])] shl 12) or
                               (ConvertHexToBin[ord(P[2])] shl 8) or
                               (ConvertHexToBin[ord(P[3])] shl 4) or
                                ConvertHexToBin[ord(P[4])];
                  case c4 of
                    // inlined Utf16CharToUtf8()
                    UTF16_HISURROGATE_MIN..UTF16_HISURROGATE_MAX:
                      c4 := ((c4 - $D7C0) shl 10) or
                         (surrogate xor UTF16_LOSURROGATE_MIN);
                    UTF16_LOSURROGATE_MIN..UTF16_LOSURROGATE_MAX:
                      c4 := ((surrogate - $D7C0) shl 10) or
                         (c4 xor UTF16_LOSURROGATE_MIN);
                  end;
                  if c4 <= $7ff then
                    c := #2
                  else if c4 <= $ffff then
                    c := #3
                  else if c4 <= $1FFFFF then
                    c := #4
                  else if c4 <= $3FFFFFF then
                    c := #5
                  else
                    c := #6;
                  extra := ord(c) - 1;
                  repeat
                    D[extra] := AnsiChar((c4 and $3f) or $80);
                    c4 := c4 shr 6;
                    dec(extra);
                  until extra = 0;
                  D^ := AnsiChar(byte(c4) or UTF8_TABLE.FirstByte[ord(c)]);
                  inc(D, ord(c));
                  inc(P, 5);
                end
                else
                begin
                  // unexpected surrogate without its pair
                  D^ := '?';
                  inc(D);
                end;
            else
              begin
                D[0] := AnsiChar($E0 or (c4 shr 12));
                D[1] := AnsiChar($80 or ((c4 shr 6) and $3F));
                D[2] := AnsiChar($80 or (c4 and $3F));
                inc(D, 3);
              end;
            end;
            continue;
          end;
          goto lit;
        until false;
        // here P^='"'
        inc(P);
        D^ := #0; // make zero-terminated
        if Len <> nil then
          Len^ := D - result;
      end;
    jtNullFirstChar: // 'n'
      if (PInteger(P)^ = NULL_LOW) and
         (jcEndOfJsonValueField in tab[P[4]]) then
         // [#0, #9, #10, #13, ' ',  ',', '}', ']']
      begin
        // null -> returns nil and WasString=false
        result := nil;
        if Len <> nil then
          Len^ := 0; // when result is converted to string
        inc(P, 4);
      end
      else
        exit;
    jtFalseFirstChar: // 'f'
      if (PInteger(P + 1)^ = FALSE_LOW2) and
         (jcEndOfJsonValueField in tab[P[5]]) then
         // [#0, #9, #10, #13, ' ',  ',', '}', ']']
      begin
        // false -> returns 'false' and WasString=false
        result := P;
        if Len <> nil then
          Len^ := 5;
        inc(P, 5);
      end
      else
        exit;
    jtTrueFirstChar: // 't'
      if (PInteger(P)^ = TRUE_LOW) and
         (jcEndOfJsonValueField in tab[P[4]]) then
         // [#0, #9, #10, #13, ' ',  ',', '}', ']']
      begin
        // true -> returns 'true' and WasString=false
        result := P;
        if Len <> nil then
          Len^ := 4;
        inc(P, 4);
      end
      else
        exit;
  else
    // leave PDest=nil to notify error
    exit;
  end;
  while not (jcEndOfJsonFieldOr0 in tab[P^]) do
    if P^ = #0 then
      // leave PDest=nil for unexpected end
      exit
    else
      // loop until #0 , ] } : delimiter
      inc(P);
  if EndOfObject <> nil then
    EndOfObject^ := P^;
  // ensure JSON value is zero-terminated, and continue after it
  if P^ <> #0 then
  begin
    P^ := #0;
    PDest := P + 1;
  end
  else
    PDest := P;
end;

function GotoEndOfJsonString2(P: PUtf8Char; tab: PJsonCharSet): PUtf8Char;
  {$ifdef HASINLINE} inline; {$endif}
begin
  // P[-1]='"' at function call
  repeat
    if not (jcJsonStringMarker in tab[P^]) then
    begin
      inc(P);   // not [#0, '"', '\']
      continue; // very fast parsing of most UTF-8 chars
    end;
    if (P^ = '"') or
       (P^ = #0) or
       (P[1] = #0) then
      // end of string/buffer, or buffer overflow detected as \#0
      break;
    inc(P, 2); // P^ was '\' -> ignore \#
  until false;
  result := P;
  // P^='"' at function return (if input was correct)
end;

function GotoEndOfJsonString(P: PUtf8Char): PUtf8Char;
begin
  // P^='"' at function call
  result := GotoEndOfJsonString2(P + 1, @JSON_CHARS);
end;

function GetJsonPropName(var Json: PUtf8Char; Len: PInteger): PUtf8Char;
var
  P, Name: PUtf8Char;
  WasString: boolean;
  EndOfObject: AnsiChar;
  tab: PJsonCharSet;
label
  e;
begin
  // should match GotoNextJsonObjectOrArray() and JsonPropNameValid()
  result := nil; // returns nil on invalid input
  P := Json;
  if P = nil then
    exit;
  while P^ <= ' ' do
  begin
    if P^ = #0 then
    begin
      Json := nil; // reached early end of input
      exit;
    end;
    inc(P);
  end;
  Name := P + 1;
  tab := @JSON_CHARS;
  if P^ = '"' then
  begin
    // handle very efficiently the most common case of unescaped double quotes
    repeat
      inc(P);
    until jcJsonStringMarker in tab[P^]; // [#0, '"', '\']
    if P^ <> '"' then
      if P^ = #0 then
        exit
      else
      begin // we need to unescape the property name (seldom encoutered)
        Name := GetJsonField(Name - 1, Json, @WasString, @EndOfObject, Len);
        if (Name <> nil) and
           WasString and
           (EndOfObject = ':') then
          result := Name;
        exit;
      end;
  end
  else if P^ = '''' then
    // single quotes won't handle nested quote character
    repeat
      inc(P);
      if P^ < ' ' then
        exit;
    until P^ = ''''
  else
  begin
    // e.g. '{age:{$gt:18}}'
    if not (jcJsonIdentifierFirstChar in tab[P^]) then
      exit; // not ['_', '0'..'9', 'a'..'z', 'A'..'Z', '$']
    repeat
      inc(P);
    until not (jcJsonIdentifier in tab[P^]);
    // not ['_', '0'..'9', 'a'..'z', 'A'..'Z', '.', '[', ']']
    if P^ = #0 then
      exit;
    dec(Name);
    if Len <> nil then
      Len^ := P - Name;
    EndOfObject := P^;
    P^ := #0; // Name should end with #0
    if not (EndOfObject in [':', '=']) then // relaxed {age=10} syntax
      repeat
        inc(P);
        if P^ = #0 then
          exit;
      until P^ in [':', '='];
    goto e;
  end;
  if Len <> nil then
    Len^ := P - Name;
  P^ := #0; // ensure Name is #0 terminated
  repeat
    inc(P);
    if P^ = #0 then
      exit;
  until P^ = ':';
e:Json := P + 1;
  result := Name;
end;

procedure GetJsonPropName(var P: PUtf8Char; out PropName: shortstring);
var
  Name: PAnsiChar;
  c: AnsiChar;
  tab: PJsonCharSet;
label
  ok;
begin
  // match GotoNextJsonObjectOrArray() and overloaded GetJsonPropName()
  PropName[0] := #0;
  if P = nil then
    exit;
  while P^ <= ' ' do
  begin
    if P^ = #0 then
    begin
      P := nil;
      exit;
    end;
    inc(P);
  end;
  Name := pointer(P);
  c := P^;
  if c = '"' then
  begin
    inc(Name);
    tab := @JSON_CHARS;
    repeat
      inc(P);
    until jcJsonStringMarker in tab[P^]; // end at [#0, '"', '\']
    if P^ <> '"' then
      exit;
ok: SetString(PropName, Name, P - Name); // note: won't unescape JSON strings
    repeat
      inc(P)
    until (P^ > ' ') or
          (P^ = #0);
    if P^ <> ':' then
    begin
      PropName[0] := #0;
      exit;
    end;
    inc(P);
  end
  else if c = '''' then
  begin
    // single quotes won't handle nested quote character
    inc(P);
    inc(Name);
    while P^ <> '''' do
      if P^ < ' ' then
        exit
      else
        inc(P);
    goto ok;
  end
  else
  begin
    // e.g. '{age:{$gt:18}}'
    tab := @JSON_CHARS;
    if not (jcJsonIdentifierFirstChar in tab[c]) then
      exit; // not ['_', '0'..'9', 'a'..'z', 'A'..'Z', '$']
    repeat
      inc(P);
    until not (jcJsonIdentifier in tab[P^]);
    // not ['_', '0'..'9', 'a'..'z', 'A'..'Z', '.', '[', ']']
    SetString(PropName, Name, P - Name);
    while (P^ <= ' ') and
          (P^ <> #0) do
      inc(P);
    if (P^ <> ':') and
       (P^ <> '=') then
    begin
      // allow both age:18 and age=18 pairs (very relaxed JSON syntax)
      PropName[0] := #0;
      exit;
    end;
    inc(P);
  end;
end;

function GotoNextJsonPropName(P: PUtf8Char; tab: PJsonCharSet): PUtf8Char;
var
  c: AnsiChar;
label
  s;
begin
  // should match GotoNextJsonObjectOrArray()
  result := nil;
  if P = nil then
    exit;
  while P^ <= ' ' do
  begin
    if P^ = #0 then
      exit;
    inc(P);
  end;
  c := P^;
  if c = '"' then
  begin
    P := GotoEndOfJsonString2(P + 1, tab);
    if P^ <> '"' then
      exit;
s:  repeat
      inc(P)
    until (P^ > ' ') or
          (P^ = #0);
    if P^ <> ':' then
      exit;
  end
  else if c = '''' then
  begin
    // single quotes won't handle nested quote character
    inc(P);
    while P^ <> '''' do
      if P^ < ' ' then
        exit
      else
        inc(P);
    goto s;
  end
  else
  begin
    // e.g. '{age:{$gt:18}}'
    if not (jcJsonIdentifierFirstChar in tab[c]) then
      exit; // not ['_', '0'..'9', 'a'..'z', 'A'..'Z', '$']
    repeat
      inc(P);
    until not (jcJsonIdentifier in tab[P^]);
    // not ['_', '0'..'9', 'a'..'z', 'A'..'Z', '.', '[', ']']
    if (P^ <= ' ') and
       (P^ <> #0) then
      inc(P);
    while (P^ <= ' ') and
          (P^ <> #0) do
      inc(P);
    if not (P^ in [':', '=']) then
      // allow both age:18 and age=18 pairs (very relaxed JSON syntax)
      exit;
  end;
  repeat
    inc(P)
  until (P^ > ' ') or
        (P^ = #0);
  result := P;
end;


{ TValuePUtf8Char }

procedure TValuePUtf8Char.ToUtf8(var Text: RawUtf8);
begin
  FastSetString(Text, Value, ValueLen);
end;

function TValuePUtf8Char.ToUtf8: RawUtf8;
begin
  FastSetString(result, Value, ValueLen);
end;

function TValuePUtf8Char.ToString: string;
begin
  Utf8DecodeToString(Value, ValueLen, result);
end;

function TValuePUtf8Char.ToInteger: PtrInt;
begin
  result := GetInteger(Value);
end;

function TValuePUtf8Char.ToCardinal: PtrUInt;
begin
  result := GetCardinal(Value);
end;

function TValuePUtf8Char.Iso8601ToDateTime: TDateTime;
begin
  result := Iso8601ToDateTimePUtf8Char(Value, ValueLen);
end;

function TValuePUtf8Char.Idem(const Text: RawUtf8): boolean;
begin
  result := (length(Text) = ValueLen) and
            ((ValueLen = 0) or
             IdemPropNameUSameLenNotNull(pointer(Text), Value, ValueLen));
end;


procedure JsonDecode(var Json: RawUtf8; const Names: array of RawUtf8;
  Values: PValuePUtf8CharArray; HandleValuesAsObjectOrArray: boolean);
begin
  JsonDecode(UniqueRawUtf8(Json), Names, Values, HandleValuesAsObjectOrArray);
end;

procedure JsonDecode(var Json: RawJson; const Names: array of RawUtf8;
  Values: PValuePUtf8CharArray; HandleValuesAsObjectOrArray: boolean);
begin
  JsonDecode(UniqueRawUtf8(RawUtf8(Json)), Names, Values, HandleValuesAsObjectOrArray);
end;

function JsonDecode(P: PUtf8Char; const Names: array of RawUtf8;
  Values: PValuePUtf8CharArray; HandleValuesAsObjectOrArray: boolean): PUtf8Char;
var
  n, i: PtrInt;
  namelen, valuelen: integer;
  name, value: PUtf8Char;
  EndOfObject: AnsiChar;
begin
  result := nil;
  if Values = nil then
    exit; // avoid GPF
  n := length(Names);
  FillCharFast(Values[0], n * SizeOf(Values[0]), 0);
  dec(n);
  if P = nil then
    exit;
  while P^ <> '{' do
    if P^ = #0 then
      exit
    else
      inc(P);
  inc(P); // jump {
  repeat
    name := GetJsonPropName(P, @namelen);
    if name = nil then
      exit;  // invalid Json content
    value := GetJsonFieldOrObjectOrArray(P, nil, @EndOfObject,
      HandleValuesAsObjectOrArray, true, @valuelen);
    if not (EndOfObject in [',', '}']) then
      exit; // invalid item separator
    for i := 0 to n do
      if (Values[i].value = nil) and
         IdemPropNameU(Names[i], name, namelen) then
      begin
        Values[i].value := value;
        Values[i].valuelen := valuelen;
        break;
      end;
  until (P = nil) or
        (EndOfObject = '}');
  if P = nil then // result=nil indicates failure -> points to #0 for end of text
    result := @NULCHAR
  else
    result := P;
end;

function JsonDecode(var Json: RawUtf8; const aName: RawUtf8; WasString: PBoolean;
  HandleValuesAsObjectOrArray: boolean): RawUtf8;
var
  P, Name, Value: PUtf8Char;
  NameLen, ValueLen: integer;
  EndOfObject: AnsiChar;
begin
  result := '';
  P := pointer(Json);
  if P = nil then
    exit;
  while P^ <> '{' do
    if P^ = #0 then
      exit
    else
      inc(P);
  inc(P); // jump {
  repeat
    Name := GetJsonPropName(P, @NameLen);
    if Name = nil then
      exit;  // invalid Json content
    Value := GetJsonFieldOrObjectOrArray(P, WasString, @EndOfObject,
      HandleValuesAsObjectOrArray, true, @ValueLen);
    if not (EndOfObject in [',', '}']) then
      exit; // invalid item separator
    if IdemPropNameU(aName, Name, NameLen) then
    begin
      FastSetString(result, Value, ValueLen);
      exit;
    end;
  until (P = nil) or
        (EndOfObject = '}');
end;

function JsonDecode(P: PUtf8Char; out Values: TNameValuePUtf8CharDynArray;
  HandleValuesAsObjectOrArray: boolean): PUtf8Char;
var
  n: PtrInt;
  field: TNameValuePUtf8Char;
  EndOfObject: AnsiChar;
begin
  {$ifdef FPC}
  Values := nil;
  {$endif FPC}
  result := nil;
  n := 0;
  if P <> nil then
  begin
    while P^ <> '{' do
      if P^ = #0 then
        exit
      else
        inc(P);
    inc(P); // jump {
    repeat
      field.Name := GetJsonPropName(P, @field.NameLen);
      if field.Name = nil then
        exit;  // invalid JSON content
      field.Value := GetJsonFieldOrObjectOrArray(P, nil, @EndOfObject,
        HandleValuesAsObjectOrArray, true, @field.ValueLen);
      if not (EndOfObject in [',', '}']) then
        exit; // invalid item separator
      if n = length(Values) then
        SetLength(Values, n + 32);
      Values[n] := field;
      inc(n);
    until (P = nil) or
          (EndOfObject = '}');
  end;
  SetLength(Values, n);
  if P = nil then // result=nil indicates failure -> points to #0 for end of text
    result := @NULCHAR
  else
    result := P;
end;

function JsonRetrieveStringField(P: PUtf8Char; out Field: PUtf8Char;
  out FieldLen: integer; ExpectNameField: boolean): PUtf8Char;
var
  tab: PJsonCharSet;
begin
  result := nil;
  // retrieve string field
  if P = nil then
    exit;
  while (P^ <= ' ') and
        (P^ <> #0) do
    inc(P);
  if P^ <> '"' then
    exit;
  inc(P);
  Field := P;
  tab := @JSON_CHARS;
  while not (jcJsonStringMarker in tab[P^]) do
    // not [#0, '"', '\']
    inc(P); // very fast parsing of most UTF-8 chars within "string"
  if P^ <> '"' then
    exit; // here P^ should be '"'
  FieldLen := P - Field;
  // check valid JSON delimiter
  repeat
    inc(P)
  until (P^ > ' ') or
        (P^ = #0);
  if ExpectNameField then
  begin
    if P^ <> ':' then
      exit; // invalid name field
  end
  else if not (P^ in ['}', ',']) then
    exit; // invalid value field
  result := P; // return either ':' for name field, or } , for value field
end;

function GlobalFindClass(classname: PUtf8Char; classnamelen: integer): TRttiCustom;
var
  name: string;
  c: TClass;
begin
  Utf8DecodeToString(classname, classnamelen, name);
  c := FindClass(name);
  if c = nil then
    result := nil
  else
    result := Rtti.RegisterClass(c);
end;

function JsonRetrieveObjectRttiCustom(var Json: PUtf8Char;
  AndGlobalFindClass: boolean): TRttiCustom;
var
  tab: PNormTable;
  P, classname: PUtf8Char;
  classnamelen: integer;
begin
  // at input, Json^ = '{'
  result := nil;
  P := GotoNextNotSpace(Json + 1);
  tab := @NormToUpperAnsi7;
  if IdemPChar(P, '"CLASSNAME":', tab) then
    inc(P, 12)
  else if IdemPChar(P, 'CLASSNAME:', tab) then
    inc(P, 10)
  else
    exit; // we expect woStoreClassName option to have been used
  P := JsonRetrieveStringField(P, classname, classnamelen, false);
  if P = nil then
    exit; // invalid (maybe too complex) Json string value
  Json := P; // Json^ is either } or ,
  result := Rtti.Find(classname, classnamelen, rkClass);
  if (result = nil) and
     AndGlobalFindClass then
    result := GlobalFindClass(classname, classnamelen);
end;

function GetJsonFieldOrObjectOrArray(var Json: PUtf8Char; WasString: PBoolean;
  EndOfObject: PUtf8Char; HandleValuesAsObjectOrArray: boolean;
  NormalizeBoolean: boolean; Len: PInteger): PUtf8Char;
var
  P, Value: PUtf8Char;
  wStr: boolean;
begin
  result := nil;
  P := Json;
  if P = nil then
    exit;
  while (P^ <= ' ') and
        (P^ <> #0) do
    inc(P);
  if HandleValuesAsObjectOrArray and
     (P^ in ['{', '[']) then
  begin
    Value := P;
    P := GotoNextJsonObjectOrArrayMax(P, nil);
    if P <> nil then
    begin
      // was a valid object or array
      if Len <> nil then
        Len^ := P - Value;
      if WasString <> nil then
        WasString^ := false;
      while (P^ <= ' ') and
            (P^ <> #0) do
        inc(P);
      if EndOfObject <> nil then
        EndOfObject^ := P^;
      if P^ <> #0 then
      begin
        P^ := #0; // make zero-terminated
        inc(P);
      end;
      Json := P;
      result := Value;
      exit;
    end;
    // will store as string even if stats with { or [
  end;
  result := GetJsonField(P, JSON, @wStr, EndOfObject, Len);
  if WasString <> nil then
    WasString^ := wStr;
  if not wStr and
     NormalizeBoolean and
     (result <> nil) then
  begin
    if PInteger(result)^ = TRUE_LOW then
      result := pointer(SmallUInt32Utf8[1]) // normalize true -> 1
    else if PInteger(result)^ = FALSE_LOW then
      result := pointer(SmallUInt32Utf8[0]) // normalize false -> 0
    else
      exit;
    if Len <> nil then
      Len^ := 1;
  end;
end;

procedure GetJsonItemAsRawJson(var P: PUtf8Char; var result: RawJson;
  EndOfObject: PAnsiChar);
var
  B: PUtf8Char;
begin
  result := '';
  if P = nil then
    exit;
  B := GotoNextNotSpace(P);
  P := GotoEndJsonItem(B);
  if P = nil then
    exit;
  FastSetString(RawUtf8(result), B, P - B);
  while (P^ <= ' ') and
        (P^ <> #0) do
    inc(P);
  if EndOfObject <> nil then
    EndOfObject^ := P^;
  if P^ <> #0 then //if P^=',' then
    repeat
      inc(P)
    until (P^ > ' ') or
          (P^ = #0);
end;

function GetJsonItemAsRawUtf8(var P: PUtf8Char; var output: RawUtf8;
  WasString: PBoolean; EndOfObject: PUtf8Char): boolean;
var
  V: PUtf8Char;
  VLen: integer;
begin
  V := GetJsonFieldOrObjectOrArray(P, WasString, EndOfObject, true, true, @VLen);
  if V = nil then // parsing error
    result := false
  else
  begin
    FastSetString(output, V, VLen);
    result := true;
  end;
end;

function GotoNextJsonObjectOrArrayInternal(P, PMax: PUtf8Char;
  EndChar: AnsiChar{$ifndef CPUX86NOTPIC} ; jsonset: PJsonCharSet{$endif}): PUtf8Char;
{$ifdef CPUX86NOTPIC} // not enough registers
var
  jsonset: TJsonCharSet absolute JSON_CHARS;
{$endif CPUX86NOTPIC}
label
  prop;
begin
  // should match GetJsonPropName()
  result := nil;
  repeat
    // main loop for quick parsing without full validation
    case JSON_TOKENS[P^] of
      jtObjectStart: // '{'
        begin
          repeat
            inc(P)
          until (P^ > ' ') or
                (P^ = #0);
          P := GotoNextJsonObjectOrArrayInternal(
                 P, PMax, '}' {$ifndef CPUX86NOTPIC}, jsonset{$endif});
          if P = nil then
            exit;
        end;
      jtArrayStart: // '['
        begin
          repeat
            inc(P)
          until (P^ > ' ') or
                (P^ = #0);
          P := GotoNextJsonObjectOrArrayInternal(
            P, PMax, ']'{$ifndef CPUX86NOTPIC}, jsonset{$endif});
          if P = nil then
            exit;
        end;
      jtAssign: // ':'
        if EndChar <> '}' then
          exit
        else
          inc(P); // syntax for JSON object only
      jtComma: // ','
        inc(P); // comma appears in both JSON objects and arrays
      jtObjectStop: // '}'
        if EndChar = '}' then
          break
        else
          exit;
      jtArrayStop: // ']'
        if EndChar = ']' then
          break
        else
          exit;
      jtDoubleQuote: // '"'
        begin
          P := GotoEndOfJsonString2(P + 1, {$ifdef CPUX86NOTPIC}@{$endif}jsonset);
          if P^ <> '"' then
            exit;
          inc(P);
        end;
      jtFirstDigit: // '-', '0'..'9'
        // '0123' excluded by JSON, but not here
        repeat
          inc(P);
        until not (jcDigitFloatChar in jsonset[P^]);
        // not ['-', '+', '0'..'9', '.', 'E', 'e']
      jtTrueFirstChar: // 't'
        if PInteger(P)^ = TRUE_LOW then
          inc(P, 4)
        else
          goto prop;
      jtFalseFirstChar: // 'f'
        if PInteger(P + 1)^ = FALSE_LOW2 then
          inc(P, 5)
        else
          goto prop;
      jtNullFirstChar: // 'n'
        if PInteger(P)^ = NULL_LOW then
          inc(P, 4)
        else
          goto prop;
      jtSingleQuote: // '''' as single-quoted identifier
        begin
          repeat
            inc(P);
            if P^ <= ' ' then
              exit;
          until P^ = '''';
          repeat
            inc(P)
          until (P^ > ' ') or
                (P^ = #0);
          if P^ <> ':' then
            exit;
        end;
      jtSlash: // '/' to allow extended /regex/ syntax
        begin
          repeat
            inc(P);
            if P^ = #0 then
              exit;
          until P^ = '/';
          repeat
            inc(P)
          until (P^ > ' ') or
                (P^ = #0);
        end;
      jtIdentifierFirstChar: // ['_', 'a'..'z', 'A'..'Z', '$']
        begin
prop:     repeat
            inc(P);
          until not (jcJsonIdentifier in jsonset[P^]);
          // not ['_', '0'..'9', 'a'..'z', 'A'..'Z', '.', '[', ']']
          while (P^ <= ' ') and
                (P^ <> #0) do
            inc(P);
          if P^ = '(' then
          begin
            // handle e.g. "born":isodate("1969-12-31")
            inc(P);
            while (P^ <= ' ') and
                  (P^ <> #0) do
              inc(P);
            if P^ = '"' then
            begin
              P := GotoEndOfJsonString2(P + 1, {$ifdef CPUX86NOTPIC}@{$endif}jsonset);
              if P^ <> '"' then
                exit;
            end;
            inc(P);
            while (P^ <= ' ') and
                  (P^ <> #0) do
              inc(P);
            if P^ <> ')' then
              exit;
            inc(P);
          end
          else if P^ <> ':' then
            exit;
        end
    else
      // unexpected character in input JSON
      exit;
    end;
    while (P^ <= ' ') and
          (P^ <> #0) do
      inc(P);
    if (PMax <> nil) and
       (P >= PMax) then
      exit;
  until P^ = EndChar;
  result := P + 1;
end;

function GotoEndJsonItemStrict(P: PUtf8Char): PUtf8Char;
var
  {$ifdef CPUX86NOTPIC}
  jsonset: TJsonCharSet absolute JSON_CHARS; // not enough registers
  {$else}
  jsonset: PJsonCharSet;
  {$endif CPUX86NOTPIC}
label
  ok, ok4;
begin
  result := nil; // to notify unexpected end
  if P = nil then
    exit;
  while (P^ <= ' ') and
        (P^ <> #0) do
    inc(P);
  {$ifndef CPUX86NOTPIC}
  jsonset := @JSON_CHARS;
  {$endif CPUX86NOTPIC}
  case JSON_TOKENS[P^] of
    // complex JSON string, object or array
    jtDoubleQuote: // '"'
      begin
        P := GotoEndOfJsonString2(P + 1, {$ifdef CPUX86NOTPIC}@{$endif}jsonset);
        if P^ <> '"' then
          exit;
        repeat
          inc(P);
ok:     until (P^ > ' ') or
              (P^ = #0);
        result := P;
        exit;
      end;
    jtArrayStart: // '['
      begin
        repeat
          inc(P)
        until (P^ > ' ') or
              (P^ = #0);
        P := GotoNextJsonObjectOrArrayInternal(
          P, nil, ']' {$ifndef CPUX86NOTPIC}, jsonset{$endif});
        if P = nil then
          exit;
        goto ok;
      end;
    jtObjectStart: // '{'
      begin
        repeat
          inc(P)
        until (P^ > ' ') or
              (P^ = #0);
        P := GotoNextJsonObjectOrArrayInternal(
          P, nil, '}' {$ifndef CPUX86NOTPIC}, jsonset{$endif});
        if P = nil then
          exit;
        goto ok;
      end;
    // strict JSON numbers and constants validation
    jtTrueFirstChar: // 't'
      if PInteger(P)^ = TRUE_LOW then
      begin
ok4:    inc(P, 4);
        goto ok;
      end;
    jtFalseFirstChar: // 'f'
      if PInteger(P + 1)^ = FALSE_LOW2 then
      begin
        inc(P, 5);
        goto ok;
      end;
    jtNullFirstChar: // 'n'
      if PInteger(P)^ = NULL_LOW then
        goto ok4;
    jtFirstDigit: // '-', '0'..'9'
      begin
        repeat
          inc(P)
        until not (jcDigitFloatChar in jsonset[P^]);
        // not ['-', '+', '0'..'9', '.', 'E', 'e']
        goto ok;
      end;
  end;
end;

function GotoEndJsonItemFast(P, PMax: PUtf8Char
  {$ifndef CPUX86NOTPIC}; tab: PJsonCharSet{$endif}): PUtf8Char;
{$ifdef CPUX86NOTPIC}
var
  tab: TJsonCharSet absolute JSON_CHARS; // not enough registers
{$endif CPUX86NOTPIC}
label
  pok, ok;
begin
  result := nil; // to notify unexpected end
  if P = nil then
    exit;
  while (P^ <= ' ') and
        (P^ <> #0) do
    inc(P);
  // handle complex JSON string, object or array
  case P^ of
    '"':
      begin
        P := GotoEndOfJsonString2(P + 1, {$ifdef CPUX86NOTPIC}@{$endif}tab);
        if (P^ <> '"') or
           ((PMax <> nil) and
            (P > PMax)) then
          exit;
        inc(P);
        goto ok;
      end;
    '[':
      begin
        repeat
          inc(P)
        until (P^ > ' ') or
              (P^ = #0);
        P := GotoNextJsonObjectOrArrayInternal(
               P, PMax, ']' {$ifndef CPUX86NOTPIC}, tab{$endif});
        goto pok;
      end;
    '{':
      begin
        repeat
          inc(P)
        until (P^ > ' ') or
              (P^ = #0);
        P := GotoNextJsonObjectOrArrayInternal(
               P, PMax, '}' {$ifndef CPUX86NOTPIC}, tab{$endif});
pok:    if P = nil then
          exit;
ok:     while (P^ <= ' ') and
              (P^ <> #0) do
          inc(P);
        result := P;
        exit;
      end;
  end;
  // quick ignore numeric or true/false/null or MongoDB extended {age:{$gt:18}}
  if jcEndOfJsonFieldOr0 in tab[P^] then // #0 , ] } :
    exit; // no value
  repeat
    inc(P);
  until jcEndOfJsonFieldNotName in tab[P^]; // : exists in MongoDB IsoDate()
  if (P^ = #0) or
     ((PMax <> nil) and
      (P > PMax)) then
    exit; // unexpected end
  result := P;
end;

function GotoEndJsonItem(P, PMax: PUtf8Char): PUtf8Char;
begin
  result := GotoEndJsonItemFast(P, PMax {$ifndef CPUX86NOTPIC}, @JSON_CHARS{$endif});
end;

function GotoNextJsonItem(P: PUtf8Char; NumberOfItemsToJump: cardinal;
  EndOfObject: PAnsiChar): PUtf8Char;
begin
  result := nil; // to notify unexpected end
  if NumberOfItemsToJump <> 0 then
  repeat
    P := GotoEndJsonItemFast(P, nil {$ifndef CPUX86NOTPIC}, @JSON_CHARS{$endif});
    if P = nil then
      exit;
    inc(P); // ignore jcEndOfJsonFieldOr0
    dec(NumberOfItemsToJump);
  until NumberOfItemsToJump = 0;
  if EndOfObject <> nil then
    EndOfObject^ := P[-1]; // return last jcEndOfJsonFieldOr0
  result := P;
end;

function GotoNextJsonObjectOrArray(P: PUtf8Char; EndChar: AnsiChar): PUtf8Char;
begin
  // should match GetJsonPropName()
  while (P^ <= ' ') and
        (P^ <> #0) do
    inc(P);
  result := GotoNextJsonObjectOrArrayInternal(
    P, nil, EndChar {$ifndef CPUX86NOTPIC}, @JSON_CHARS{$endif});
end;

function GotoNextJsonObjectOrArrayMax(P, PMax: PUtf8Char): PUtf8Char;
var
  EndChar: AnsiChar;
begin
  // should match GetJsonPropName()
  result := nil; // mark error or unexpected end (#0)
  while (P^ <= ' ') and
        (P^ <> #0) do
    inc(P);
  case P^ of
    '[':
      EndChar := ']';
    '{':
      EndChar := '}';
  else
    exit;
  end;
  repeat
    inc(P)
  until (P^ > ' ') or
        (P^ = #0);
  result := GotoNextJsonObjectOrArrayInternal(
    P, PMax, EndChar {$ifndef CPUX86NOTPIC}, @JSON_CHARS{$endif});
end;

function GotoNextJsonObjectOrArray(P: PUtf8Char): PUtf8Char;
begin
  result := GotoNextJsonObjectOrArrayMax(P, nil);
end;

function JsonArrayCount(P: PUtf8Char): integer;
var
  n: integer;
  {$ifndef CPUX86NOTPIC}
  tab: PJsonCharSet;
  {$endif CPUX86NOTPIC}
begin
  result := -1;
  n := 0;
  {$ifndef CPUX86NOTPIC}
  tab := @JSON_CHARS;
  {$endif CPUX86NOTPIC}
  P := GotoNextNotSpace(P);
  if P^ <> ']' then
    repeat
      P := GotoEndJsonItemFast(P, nil {$ifndef CPUX86NOTPIC}, tab{$endif});
      if P = nil then
        // invalid content, or #0 reached
        exit;
      inc(n);
      if P^ <> ',' then
        break;
      inc(P);
    until false;
  if P^ = ']' then
    result := n;
end;

function JsonArrayCount(P, PMax: PUtf8Char): integer;
{$ifndef CPUX86NOTPIC}
var
  tab: PJsonCharSet;
{$endif CPUX86NOTPIC}
begin
  result := 0;
  P := GotoNextNotSpace(P);
  {$ifndef CPUX86NOTPIC}
  tab := @JSON_CHARS;
  {$endif CPUX86NOTPIC}
  if P^ <> ']' then
    while P < PMax do
    begin
      P := GotoEndJsonItemFast(P, PMax{$ifndef CPUX86NOTPIC}, tab{$endif});
      if P = nil then
        // invalid content, or #0/PMax reached
        break;
      inc(result);
      if P^ <> ',' then
        break;
      inc(P);
    end;
  if (P = nil) or
     (P^ <> ']') then
    // aborted when PMax or #0 was reached or the JSON input was invalid
    if result = 0 then
      dec(result) // -1 to ensure the caller tries to get something
    else
      result := -result; // return the current count as negative
end;

function JsonArrayDecode(P: PUtf8Char; out Values: TPUtf8CharDynArray): boolean;
var
  n, max: integer;
begin
  result := false;
  max := 0;
  n := 0;
  P := GotoNextNotSpace(P);
  if P^ <> ']' then
    repeat
      if max = n then
      begin
        max := NextGrow(max);
        SetLength(Values, max);
      end;
      Values[n] := P;
      P := GotoEndJsonItem(P);
      if P = nil then
        exit; // invalid content, or #0 reached
      if P^ <> ',' then
        break;
      inc(P);
    until false;
  if P^ = ']' then
  begin
    SetLength(Values, n);
    result := true;
  end
  else
    Values := nil;
end;

function JsonArrayItem(P: PUtf8Char; Index: integer): PUtf8Char;
begin
  if P <> nil then
  begin
    P := GotoNextNotSpace(P);
    if P^ = '[' then
    begin
      P := GotoNextNotSpace(P + 1);
      if P^ <> ']' then
        repeat
          if Index <= 0 then
          begin
            result := P;
            exit;
          end;
          P := GotoEndJsonItem(P);
          if (P = nil) or
             (P^ <> ',') then
            break; // invalid content or #0 reached
          inc(P);
          dec(Index);
        until false;
    end;
  end;
  result := nil;
end;

function JsonObjectPropCount(P: PUtf8Char): integer;
var
  n: integer;
  {$ifndef CPUX86NOTPIC}
  tab: PJsonCharSet;
  {$endif CPUX86NOTPIC}
begin
  {$ifndef CPUX86NOTPIC}
  tab := @JSON_CHARS;
  {$endif CPUX86NOTPIC}
  result := -1;
  n := 0;
  P := GotoNextNotSpace(P);
  if P^ <> '}' then
    repeat
      P := GotoNextJsonPropName(P,
            {$ifdef CPUX86NOTPIC} @JSON_CHARS {$else} tab {$endif});
      if P = nil then
        exit; // invalid field name
      P := GotoEndJsonItemFast(P, nil {$ifndef CPUX86NOTPIC}, tab{$endif});
      if P = nil then
        exit; // invalid content, or #0 reached
      inc(n);
      if P^ <> ',' then
        break;
      inc(P);
    until false;
  if P^ = '}' then
    result := n;
end;

function JsonObjectItem(P: PUtf8Char; const PropName: RawUtf8;
  PropNameFound: PRawUtf8): PUtf8Char;
var
  name: shortstring; // no memory allocation nor P^ modification
  PropNameLen: integer;
  PropNameUpper: array[byte] of AnsiChar;
begin
  if P <> nil then
  begin
    P := GotoNextNotSpace(P);
    PropNameLen := length(PropName);
    if PropNameLen <> 0 then
    begin
      if PropName[PropNameLen] = '*' then
      begin
        UpperCopy255Buf(PropNameUpper{%H-},
          pointer(PropName), PropNameLen - 1)^ := #0;
        PropNameLen := 0;
      end;
      if P^ = '{' then
        P := GotoNextNotSpace(P + 1);
      if P^ <> '}' then
        repeat
          GetJsonPropName(P, name);
          if (name[0] = #0) or
             (name[0] > #200) then
            break;
          while (P^ <= ' ') and
                (P^ <> #0) do
            inc(P);
          if PropNameLen = 0 then // 'PropName*'
          begin
            name[ord(name[0]) + 1] := #0; // make ASCIIZ
            if IdemPChar(@name[1], PropNameUpper) then
            begin
              if PropNameFound <> nil then
                FastSetString(PropNameFound^, @name[1], ord(name[0]));
              result := P;
              exit;
            end;
          end
          else if IdemPropName(name, pointer(PropName), PropNameLen) then
          begin
            result := P;
            exit;
          end;
          P := GotoEndJsonItem(P);
          if (P = nil) or
             (P^ <> ',') then
            break; // invalid content, or #0 reached
          inc(P);
        until false;
    end;
  end;
  result := nil;
end;

function JsonObjectByPath(JsonObject, PropPath: PUtf8Char): PUtf8Char;
var
  objName: RawUtf8;
begin
  result := nil;
  if (JsonObject = nil) or
     (PropPath = nil) then
    exit;
  repeat
    GetNextItem(PropPath, '.', objName);
    if objName = '' then
      exit;
    JsonObject := JsonObjectItem(JsonObject, objName);
    if JsonObject = nil then
      exit;
  until PropPath = nil; // found full name scope
  result := JsonObject;
end;

function JsonObjectsByPath(JsonObject, PropPath: PUtf8Char): RawUtf8;
var
  itemName, objName, propNameFound, objPath: RawUtf8;
  start, ending, obj: PUtf8Char;
  WR: TBaseWriter;
  temp: TTextWriterStackBuffer;

  procedure AddFromStart(const name: RawUtf8);
  begin
    start := GotoNextNotSpace(start);
    ending := GotoEndJsonItem(start);
    if ending = nil then
      exit;
    if WR = nil then
    begin
      WR := TBaseWriter.CreateOwnedStream(temp);
      WR.Add('{');
    end
    else
      WR.AddComma;
    WR.AddFieldName(name);
    while (ending > start) and
          (ending[-1] <= ' ') do
      dec(ending); // trim right
    WR.AddNoJsonEscape(start, ending - start);
  end;

begin
  result := '';
  if (JsonObject = nil) or
     (PropPath = nil) then
    exit;
  WR := nil;
  try
    repeat
      GetNextItem(PropPath, ',', itemName);
      if itemName = '' then
        break;
      if itemName[length(itemName)] <> '*' then
      begin
        start := JsonObjectByPath(JsonObject, pointer(itemName));
        if start <> nil then
          AddFromStart(itemName);
      end
      else
      begin
        objPath := '';
        obj := pointer(itemName);
        repeat
          GetNextItem(obj, '.', objName);
          if objName = '' then
            exit;
          propNameFound := '';
          JsonObject := JsonObjectItem(JsonObject, objName, @propNameFound);
          if JsonObject = nil then
            exit;
          if obj = nil then
          begin
            // found full name scope
            start := JsonObject;
            repeat
              AddFromStart(objPath + propNameFound);
              ending := GotoNextNotSpace(ending);
              if ending^ <> ',' then
                break;
              propNameFound := '';
              start := JsonObjectItem(GotoNextNotSpace(ending + 1), objName, @propNameFound);
            until start = nil;
            break;
          end
          else
            objPath := objPath + objName + '.';
        until false;
      end;
    until PropPath = nil;
    if WR <> nil then
    begin
      WR.Add('}');
      WR.SetText(result);
    end;
  finally
    WR.Free;
  end;
end;

function JsonObjectAsJsonArrays(Json: PUtf8Char; out keys, values: RawUtf8): integer;
var
  wk, wv: TBaseWriter;
  kb, ke, vb, ve: PUtf8Char;
  temp1, temp2: TTextWriterStackBuffer;
  n: integer;
begin
  result := -1;
  if (Json = nil) or
     (Json^ <> '{') then
    exit;
  n := 0;
  wk := TBaseWriter.CreateOwnedStream(temp1);
  wv := TBaseWriter.CreateOwnedStream(temp2);
  try
    wk.Add('[');
    wv.Add('[');
    kb := Json + 1;
    repeat
      ke := GotoEndJsonItem(kb);
      if (ke = nil) or
         (ke^ <> ':') then
        exit; // invalid input content
      vb := ke + 1;
      ve := GotoEndJsonItem(vb);
      if (ve = nil) or
         not (ve^ in [',', '}']) then
        exit;
      wk.AddNoJsonEscape(kb, ke - kb);
      wk.AddComma;
      wv.AddNoJsonEscape(vb, ve - vb);
      wv.AddComma;
      kb := ve + 1;
      inc(n);
    until ve^ = '}';
    wk.CancelLastComma;
    wk.Add(']');
    wk.SetText(keys);
    wv.CancelLastComma;
    wv.Add(']');
    wv.SetText(values);
    result := n; // success
  finally
    wv.Free;
    wk.Free;
  end;
end;

function TryRemoveComment(P: PUtf8Char): PUtf8Char;
  {$ifdef HASINLINE} inline; {$endif}
begin
  result := P + 1;
  case result^ of
    '/':
      begin // this is // comment - replace by ' '
        dec(result);
        repeat
          result^ := ' ';
          inc(result)
        until result^ in [#0, #10, #13];
        if result^ <> #0 then
          inc(result);
      end;
    '*':
      begin // this is /* comment - replace by ' ' but keep CRLF
        result[-1] := ' ';
        repeat
          if not (result^ in [#10, #13]) then
            result^ := ' '; // keep CRLF for correct line numbering (e.g. for error)
          inc(result);
          if PWord(result)^ = ord('*') + ord('/') shl 8 then
          begin
            PWord(result)^ := $2020;
            inc(result, 2);
            break;
          end;
        until result^ = #0;
      end;
  end;
end;

procedure RemoveCommentsFromJson(P: PUtf8Char);
var
  PComma: PUtf8Char;
begin // replace comments by ' ' characters which will be ignored by parser
  if P <> nil then
    while P^ <> #0 do
    begin
      case P^ of
        '"':
          begin
            P := GotoEndOfJSONString(P + 1);
            if P^ <> '"' then
              exit
            else
              inc(P);
          end;
        '/':
          P := TryRemoveComment(P);
        ',':
          begin // replace trailing comma by space for strict JSON parsers
            PComma := P;
            repeat
              inc(P)
            until (P^ > ' ') or
                  (P^ = #0);
            if P^ = '/' then
              P := TryRemoveComment(P);
            while (P^ <= ' ') and
                  (P^ <> #0) do
              inc(P);
            if P^ in ['}', ']'] then
              PComma^ := ' '; // see https://github.com/synopse/mORMot/pull/349
          end;
      else
        inc(P);
      end;
    end;
end;

function RemoveCommentsFromJson(const s: RawUtf8): RawUtf8;
begin
  if PosExChar('/', s) = 0 then
    result := s
  else
  begin
    FastSetString(result, pointer(s), length(s));
    RemoveCommentsFromJson(pointer(s)); // remove in-place
  end;
end;

function ParseEndOfObject(P: PUtf8Char; out EndOfObject: AnsiChar): PUtf8Char;
var
  tab: PJsonCharSet;
begin
  if P <> nil then
  begin
    tab := @JSON_CHARS; // mimics GetJsonField()
    while not (jcEndOfJsonFieldOr0 in tab[P^]) do
      inc(P); // not #0 , ] } :
    EndOfObject := P^;
    if P^ <> #0 then
      repeat
        inc(P); // ignore trailing , ] } and any successive spaces
      until (P^ > ' ') or
            (P^ = #0);
  end;
  result := P;
end;

function GetSetNameValue(Names: PShortString; MaxValue: integer;
  var P: PUtf8Char; out EndOfObject: AnsiChar): QWord;
var
  Text: PUtf8Char;
  WasString: boolean;
  TextLen, i: integer;
begin
  result := 0;
  if (P = nil) or
     (Names = nil) or
     (MaxValue < 0) then
    exit;
  while (P^ <= ' ') and
        (P^ <> #0) do
    inc(P);
  if P^ = '[' then
  begin
    repeat
      inc(P)
    until (P^ > ' ') or
          (P^ = #0);
    if P^ = ']' then
      inc(P)
    else
    begin
      repeat
        Text := GetJsonField(P, P, @WasString, @EndOfObject, @TextLen);
        if (Text = nil) or
           not WasString then
        begin
          P := nil; // invalid input (expects a JSON array of strings)
          exit;
        end;
        if Text^ = '*' then
        begin
          if MaxValue < 32 then
            result := ALLBITS_CARDINAL[MaxValue + 1]
          else
            result := QWord(-1);
          break;
        end;
        if Text^ in ['a'..'z'] then
          i := FindShortStringListExact(names, MaxValue, Text, TextLen)
        else
          i := -1;
        if i < 0 then
          i := FindShortStringListTrimLowerCase(names, MaxValue, Text, TextLen);
        if i >= 0 then
          SetBitPtr(@result, i);
        // unknown enum names (i=-1) would just be ignored
      until EndOfObject = ']';
      if P = nil then
        exit; // avoid GPF below if already reached the input end
    end;
    P := ParseEndOfObject(P, EndOfObject); // mimics GetJsonField()
  end
  else
    SetQWord(GetJsonField(P, P, nil, @EndOfObject), result);
end;

function GetSetNameValue(Info: PRttiInfo;
  var P: PUtf8Char; out EndOfObject: AnsiChar): QWord;
var
  Names: PShortString;
  MaxValue: integer;
begin
  if (Info <> nil) and
     (Info^.Kind = rkSet) and
     (Info^.SetEnumType(Names, MaxValue) <> nil) then
    result := GetSetNameValue(Names, MaxValue, P, EndOfObject)
  else
    result := 0;
end;

function UrlEncodeJsonObject(const UriName: RawUtf8; ParametersJson: PUtf8Char;
  const PropNamesToIgnore: array of RawUtf8; IncludeQueryDelimiter: boolean): RawUtf8;
var
  i, j: PtrInt;
  sep: AnsiChar;
  Params: TNameValuePUtf8CharDynArray;
  temp: TTextWriterStackBuffer;
begin
  if ParametersJson = nil then
    result := UriName
  else
    with TBaseWriter.CreateOwnedStream(temp) do
    try
      AddString(UriName);
      if (JsonDecode(ParametersJson, Params, true) <> nil) and
         (Params <> nil) then
      begin
        sep := '?';
        for i := 0 to length(Params) - 1 do
          with Params[i] do
          begin
            for j := 0 to high(PropNamesToIgnore) do
              if IdemPropNameU(PropNamesToIgnore[j], Name, NameLen) then
              begin
                NameLen := 0;
                break;
              end;
            if NameLen = 0 then
              continue;
            if IncludeQueryDelimiter then
              Add(sep);
            AddNoJsonEscape(Name, NameLen);
            Add('=');
            AddString(UrlEncode(Value));
            sep := '&';
            IncludeQueryDelimiter := true;
          end;
      end;
      SetText(result);
    finally
      Free;
    end;
end;

function UrlEncodeJsonObject(const UriName, ParametersJson: RawUtf8;
  const PropNamesToIgnore: array of RawUtf8; IncludeQueryDelimiter: boolean): RawUtf8;
var
  temp: TSynTempBuffer;
begin
  temp.Init(ParametersJson);
  try
    result := UrlEncodeJsonObject(
      UriName, temp.buf, PropNamesToIgnore, IncludeQueryDelimiter);
  finally
    temp.Done;
  end;
end;

function ObjArrayToJson(const aObjArray;
  aOptions: TTextWriterWriteObjectOptions): RawUtf8;
var
  temp: TTextWriterStackBuffer;
begin
  with TTextWriter.CreateOwnedStream(temp) do
  try
    if woEnumSetsAsText in aOptions then
      CustomOptions := CustomOptions + [twoEnumSetsAsTextInRecord];
    AddObjArrayJson(aObjArray, aOptions);
    SetText(result);
  finally
    Free;
  end;
end;

function JsonEncode(const NameValuePairs: array of const): RawUtf8;
var
  temp: TTextWriterStackBuffer;
begin
  if high(NameValuePairs) < 1 then
    // return void JSON object on error
    result := '{}'
  else
    with TTextWriter.CreateOwnedStream(temp) do
    try
      AddJsonEscape(NameValuePairs);
      SetText(result);
    finally
      Free
    end;
end;

function JsonEncode(const Format: RawUtf8;
  const Args, Params: array of const): RawUtf8;
var
  temp: TTextWriterStackBuffer;
begin
  with TTextWriter.CreateOwnedStream(temp) do
  try
    AddJson(Format, Args, Params);
    SetText(result);
  finally
    Free
  end;
end;

function JsonEncodeArrayDouble(const Values: array of double): RawUtf8;
var
  W: TTextWriter;
  temp: TTextWriterStackBuffer;
begin
  W := TTextWriter.CreateOwnedStream(temp);
  try
    W.Add('[');
    W.AddCsvDouble(Values);
    W.Add(']');
    W.SetText(result);
  finally
    W.Free
  end;
end;

function JsonEncodeArrayUtf8(const Values: array of RawUtf8): RawUtf8;
var
  W: TTextWriter;
  temp: TTextWriterStackBuffer;
begin
  W := TTextWriter.CreateOwnedStream(temp);
  try
    W.Add('[');
    W.AddCsvUtf8(Values);
    W.Add(']');
    W.SetText(result);
  finally
    W.Free
  end;
end;

function JsonEncodeArrayInteger(const Values: array of integer): RawUtf8;
var
  W: TTextWriter;
  temp: TTextWriterStackBuffer;
begin
  W := TTextWriter.CreateOwnedStream(temp);
  try
    W.Add('[');
    W.AddCsvInteger(Values);
    W.Add(']');
    W.SetText(result);
  finally
    W.Free
  end;
end;

function JsonEncodeArrayOfConst(const Values: array of const;
  WithoutBraces: boolean): RawUtf8;
begin
  JsonEncodeArrayOfConst(Values, WithoutBraces, result);
end;

procedure JsonEncodeArrayOfConst(const Values: array of const;
  WithoutBraces: boolean; var result: RawUtf8);
var
  temp: TTextWriterStackBuffer;
begin
  if length(Values) = 0 then
    if WithoutBraces then
      result := ''
    else
      result := '[]'
  else
    with TTextWriter.CreateOwnedStream(temp) do
    try
      if not WithoutBraces then
        Add('[');
      AddCsvConst(Values);
      if not WithoutBraces then
        Add(']');
      SetText(result);
    finally
      Free
    end;
end;

procedure JsonEncodeNameSQLValue(const Name, SQLValue: RawUtf8;
  var result: RawUtf8);
var
  temp: TTextWriterStackBuffer;
begin
  if (SQLValue <> '') and
     (SQLValue[1] in ['''', '"']) then
    // unescape SQL quoted string value into a valid JSON string
    with TTextWriter.CreateOwnedStream(temp) do
    try
      Add('{', '"');
      AddNoJsonEscapeUtf8(Name);
      Add('"', ':');
      AddQuotedStringAsJson(SQLValue);
      Add('}');
      SetText(result);
    finally
      Free;
    end
  else
    // Value is a number or null/true/false
    result := '{"' + Name + '":' + SQLValue + '}';
end;


procedure QuotedStrJson(P: PUtf8Char; PLen: PtrInt; var result: RawUtf8;
  const aPrefix, aSuffix: RawUtf8);
var
  temp: TTextWriterStackBuffer;
  Lp, Ls: PtrInt;
  D: PUtf8Char;
begin
  if (P = nil) or
     (PLen <= 0) then
    result := '""'
  else if (pointer(result) = pointer(P)) or
          NeedsJsonEscape(P, PLen) then
    // use TTextWriter.AddJsonEscape() for proper JSON escape
    with TTextWriter.CreateOwnedStream(temp) do
    try
      AddString(aPrefix);
      Add('"');
      AddJsonEscape(P, PLen);
      Add('"');
      AddString(aSuffix);
      SetText(result);
      exit;
    finally
      Free;
    end
  else
  begin
    // direct allocation if no JSON escape is needed
    Lp := length(aPrefix);
    Ls := length(aSuffix);
    FastSetString(result, nil, PLen + Lp + Ls + 2);
    D := pointer(result); // we checked dest result <> source P above
    if Lp > 0 then
    begin
      MoveFast(pointer(aPrefix)^, D^, Lp);
      inc(D, Lp);
    end;
    D^ := '"';
    MoveFast(P^, D[1], PLen);
    inc(D, PLen);
    D[1] := '"';
    if Ls > 0 then
      MoveFast(pointer(aSuffix)^, D[2], Ls);
  end;
end;

procedure QuotedStrJson(const aText: RawUtf8; var result: RawUtf8;
  const aPrefix, aSuffix: RawUtf8);
begin
  QuotedStrJson(pointer(aText), Length(aText), result, aPrefix, aSuffix);
end;

function QuotedStrJson(const aText: RawUtf8): RawUtf8;
begin
  QuotedStrJson(pointer(aText), Length(aText), result, '', '');
end;

procedure JsonBufferReformat(P: PUtf8Char; out result: RawUtf8;
  Format: TTextWriterJsonFormat);
var
  temp: array[word] of byte; // 64KB buffer
begin
  if P <> nil then
    with TTextWriter.CreateOwnedStream(@temp, SizeOf(temp)) do
    try
      AddJsonReformat(P, Format, nil);
      SetText(result);
    finally
      Free;
    end;
end;

function JsonReformat(const Json: RawUtf8; Format: TTextWriterJsonFormat): RawUtf8;
var
  tmp: TSynTempBuffer;
begin
  tmp.Init(Json);
  try
    JsonBufferReformat(tmp.buf, result, Format);
  finally
    tmp.Done;
  end;
end;

function JsonBufferReformatToFile(P: PUtf8Char; const Dest: TFileName;
  Format: TTextWriterJsonFormat): boolean;
var
  F: TFileStream;
  temp: array[word] of word; // 128KB
begin
  try
    F := TFileStream.Create(Dest, fmCreate);
    try
      with TTextWriter.Create(F, @temp, SizeOf(temp)) do
      try
        AddJsonReformat(P, Format, nil);
        FlushFinal;
      finally
        Free;
      end;
      result := true;
    finally
      F.Free;
    end;
  except
    on Exception do
      result := false;
  end;
end;

function JsonReformatToFile(const Json: RawUtf8; const Dest: TFileName;
  Format: TTextWriterJsonFormat): boolean;
var
  tmp: TSynTempBuffer;
begin
  tmp.Init(Json);
  try
    result := JsonBufferReformatToFile(tmp.buf, Dest, Format);
  finally
    tmp.Done;
  end;
end;


function FormatUtf8(const Format: RawUtf8; const Args, Params: array of const;
  JsonFormat: boolean): RawUtf8;
var
  A, P: PtrInt;
  F, FDeb: PUtf8Char;
  isParam: AnsiChar;
  toquote: TTempUtf8;
  temp: TTextWriterStackBuffer;
begin
  if (Format = '') or
     ((high(Args) < 0) and
      (high(Params) < 0)) then
    // no formatting to process, but may be a const
    // -> make unique since e.g. _JsonFmt() will parse it in-place
    FastSetString(result, pointer(Format), length(Format))
  else if high(Params) < 0 then
    // faster function with no ?
    FormatUtf8(Format, Args, result)
  else if Format = '%' then
    // optimize raw conversion
    VarRecToUtf8(Args[0], result)
  else
    // handle any number of parameters with minimal memory allocations
    with TTextWriter.CreateOwnedStream(temp) do
    try
      A := 0;
      P := 0;
      F := pointer(Format);
      while F^ <> #0 do
      begin
        if (F^ <> '%') and
           (F^ <> '?') then
        begin
          // handle plain text between % ? markers
          FDeb := F;
          repeat
            inc(F);
          until F^ in [#0, '%', '?'];
          AddNoJsonEscape(FDeb, F - FDeb);
          if F^ = #0 then
            break;
        end;
        isParam := F^;
        inc(F); // jump '%' or '?'
        if (isParam = '%') and
           (A <= high(Args)) then
        begin
          // handle % substitution
          if Args[A].VType = vtObject then
            AddShort(ClassNameShort(Args[A].VObject)^)
          else
            Add(Args[A]);
          inc(A);
        end
        else if (isParam = '?') and
                (P <= high(Params)) then
        begin
          // handle ? substitution as JSON or SQL
          if JsonFormat then
            AddJsonEscape(Params[P]) // does the JSON magic including "quotes"
          else
          begin
            Add(':', '('); // markup for SQL parameter binding
            case Params[P].VType of
              vtBoolean, vtInteger, vtInt64 {$ifdef FPC} , vtQWord {$endif},
              vtCurrency, vtExtended:
                Add(Params[P]) // numbers or boolean don't need any SQL quoting
            else
              begin
                VarRecToTempUtf8(Params[P], toquote);
                AddQuotedStr(toquote.Text, toquote.Len, ''''); // double quote
                if toquote.TempRawUtf8 <> nil then
                  RawUtf8(toquote.TempRawUtf8) := ''; // release temp memory
              end;
            end;
            Add(')', ':');
          end;
          inc(P);
        end
        else
        begin
          // no more available Args or Params -> add all remaining text
          AddNoJsonEscape(F, length(Format) - (F - pointer(Format)));
          break;
        end;
      end;
      SetText(result);
    finally
      Free;
    end;
end;



{ ********** Low-Level JSON Serialization for all TRttiParserType }

procedure TTextWriter.BlockAfterItem(Options: TTextWriterWriteObjectOptions);
begin
  // defined here for proper inlining
  AddComma;
  if woHumanReadable in Options then
    AddCRAndIndent;
end;

{ TJsonSaveContext }

procedure TJsonSaveContext.Init(WR: TTextWriter;
  WriteOptions: TTextWriterWriteObjectOptions; Rtti: TRttiCustom);
begin
  W := WR;
  if Rtti <> nil then
    WriteOptions := WriteOptions + TRttiJson(Rtti).fIncludeWriteOptions;
  Options := WriteOptions;
  Info := Rtti;
  Prop := nil;
end;

procedure TJsonSaveContext.Add64(Value: PInt64; UnSigned: boolean);
begin
  if woInt64AsHex in Options then
    if Value^ = 0 then
      W.Add('"', '"')
    else
      W.AddBinToHexDisplayLower(Value, SizeOf(Value^), '"')
  else if UnSigned then
    W.AddQ(PQWord(Value)^)
  else
    W.Add(Value^);
end;

procedure TJsonSaveContext.AddShort(PS: PShortString);
begin
  W.Add('"');
  if twoTrimLeftEnumSets in W.CustomOptions then
    W.AddTrimLeftLowerCase(PS)
  else
    W.AddShort(PS^);
  W.Add('"');
end;

procedure TJsonSaveContext.AddShortBoolean(PS: PShortString; Value: boolean);
begin
  AddShort(PS);
  W.Add(':');
  W.Add(Value);
end;

procedure TJsonSaveContext.AddDateTime(Value: PDateTime; WithMS: boolean);
var
  d: double;
begin
  if woDateTimeWithMagic in Options then
    W.AddShorter(JSON_SQLDATE_MAGIC_QUOTE_STR)
  else
    W.Add('"');
  d := unaligned(Value^);
  W.AddDateTime(d, WithMS);
  if woDateTimeWithZSuffix in Options then
    if frac(d) = 0 then // FireFox can't decode short form "2017-01-01Z"
      W.AddShort('T00:00:00Z') // the same pattern for date and dateTime
    else
      W.Add('Z');
  W.Add('"');
end;


procedure _JS_Boolean(Data: PBoolean; const Ctxt: TJsonSaveContext);
begin
  Ctxt.W.Add(Data^);
end;

procedure _JS_Byte(Data: PByte; const Ctxt: TJsonSaveContext);
begin
  Ctxt.W.AddU(Data^);
end;

procedure _JS_Cardinal(Data: PCardinal; const Ctxt: TJsonSaveContext);
begin
  Ctxt.W.AddU(Data^);
end;

procedure _JS_Currency(Data: PInt64; const Ctxt: TJsonSaveContext);
begin
  Ctxt.W.AddCurr64(Data);
end;

procedure _JS_Double(Data: PDouble; const Ctxt: TJsonSaveContext);
begin
  Ctxt.W.AddDouble(unaligned(Data^));
end;

procedure _JS_Extended(Data: PSynExtended; const Ctxt: TJsonSaveContext);
begin
  Ctxt.W.AddDouble({$ifndef TSYNEXTENDED80}unaligned{$endif}(Data^));
end;

procedure _JS_Int64(Data: PInt64; const Ctxt: TJsonSaveContext);
begin
  Ctxt.Add64(Data, {unsigned=}false);
end;

procedure _JS_Integer(Data: PInteger; const Ctxt: TJsonSaveContext);
begin
  Ctxt.W.Add(Data^);
end;

procedure _JS_QWord(Data: PInt64; const Ctxt: TJsonSaveContext);
begin
  Ctxt.Add64(Data, {unsigned=}true);
end;

procedure _JS_RawByteString(Data: PRawByteString; const Ctxt: TJsonSaveContext);
begin
  if (rcfIsRawBlob in Ctxt.Info.Cache.Flags) and
     not (woRawBlobAsBase64 in Ctxt.Options) then
    Ctxt.W.AddNull
  else
    Ctxt.W.WrBase64(pointer(Data^), length(Data^), {withmagic=}true);
end;

procedure _JS_RawJson(Data: PRawJson; const Ctxt: TJsonSaveContext);
begin
  Ctxt.W.AddRawJson(Data^);
end;

procedure _JS_RawUtf8(Data: PPAnsiChar; const Ctxt: TJsonSaveContext);
begin
  Ctxt.W.Add('"');
  if Data^ <> nil then
    with PStrRec(Data^ - SizeOf(TStrRec))^ do
      // will handle RawUtf8 but also AnsiString, WinAnsiString and RawUnicode
      Ctxt.W.AddAnyAnsiBuffer(Data^, length, twJsonEscape,
       {$ifdef HASCODEPAGE} codePage {$else} Ctxt.Info.Cache.CodePage {$endif});
  Ctxt.W.Add('"');
end;

procedure _JS_Single(Data: PSingle; const Ctxt: TJsonSaveContext);
begin
  Ctxt.W.AddSingle(Data^);
end;

procedure _JS_Unicode(Data: PPWord; const Ctxt: TJsonSaveContext);
begin
  Ctxt.W.Add('"');
  Ctxt.W.AddJsonEscapeW(Data^);
  Ctxt.W.Add('"');
end;

procedure _JS_DateTime(Data: PDateTime; const Ctxt: TJsonSaveContext);
begin
  Ctxt.AddDateTime(Data, {withms=}false);
end;

procedure _JS_DateTimeMS(Data: PDateTime; const Ctxt: TJsonSaveContext);
begin
  Ctxt.AddDateTime(Data, {withms=}true);
end;

procedure _JS_GUID(Data: PGUID; const Ctxt: TJsonSaveContext);
begin
  Ctxt.W.Add(Data, '"');
end;

procedure _JS_Hash(Data: pointer; const Ctxt: TJsonSaveContext);
begin
  Ctxt.W.AddBinToHexDisplayLower(Data, Ctxt.Info.Size, '"');
end;

procedure _JS_Binary(Data: pointer; const Ctxt: TJsonSaveContext);
begin
  if IsZeroSmall(Data, Ctxt.Info.BinarySize) then
    Ctxt.W.Add('"', '"') // serialize "" for 0 value
  else
    Ctxt.W.AddBinToHexDisplayLower(Data, Ctxt.Info.BinarySize, '"');
end;

procedure _JS_TimeLog(Data: PInt64; const Ctxt: TJsonSaveContext);
begin
  if woTimeLogAsText in Ctxt.Options then
    Ctxt.W.AddTimeLog(Data, '"')
  else
    Ctxt.Add64(Data, true);
end;

procedure _JS_UnixTime(Data: PInt64; const Ctxt: TJsonSaveContext);
begin
  if woTimeLogAsText in Ctxt.Options then
    Ctxt.W.AddUnixTime(Data, '"')
  else
    Ctxt.Add64(Data, true);
end;

procedure _JS_UnixMSTime(Data: PInt64; const Ctxt: TJsonSaveContext);
begin
  if woTimeLogAsText in Ctxt.Options then
    Ctxt.W.AddUnixMSTime(Data, {withms=}true, '"')
  else
    Ctxt.Add64(Data, true);
end;

procedure _JS_Variant(Data: PVariant; const Ctxt: TJsonSaveContext);
begin
  Ctxt.W.AddVariant(Data^);
end;

procedure _JS_WinAnsi(Data: PWinAnsiString; const Ctxt: TJsonSaveContext);
begin
  Ctxt.W.Add('"');
  Ctxt.W.AddAnyAnsiBuffer(pointer(Data^), length(Data^), twJsonEscape, CODEPAGE_US);
  Ctxt.W.Add('"');
end;

procedure _JS_Word(Data: PWord; const Ctxt: TJsonSaveContext);
begin
  Ctxt.W.AddU(Data^);
end;

procedure _JS_Interface(Data: PInterface; const Ctxt: TJsonSaveContext);
begin
  Ctxt.W.AddNull;
end;

procedure _JS_ID(Data: PInt64; const Ctxt: TJsonSaveContext);
var
  _str: shortstring;
begin
  Ctxt.W.Add(Data^);
  if woIDAsIDstr in Ctxt.Options then
  begin
    Ctxt.W.BlockAfterItem(Ctxt.Options);
    if (Ctxt.Prop <> nil) and
       (Ctxt.Prop^.Name <> '') then
    begin
      Ansi7StringToShortString(Ctxt.Prop^.Name, _str);
      AppendShort('_str', _str);
      Ctxt.W.WriteObjectPropNameShort(_str, Ctxt.Options);
    end
    else
      Ctxt.W.WriteObjectPropNameShort('ID_str', Ctxt.Options);
    Ctxt.W.Add('"');
    Ctxt.W.Add(Data^);
    Ctxt.W.Add('"');
  end;
end;

procedure _JS_Enumeration(Data: PByte; const Ctxt: TJsonSaveContext);
var
  o: TTextWriterOptions;
  PS: PShortString;
begin
  o := Ctxt.W.CustomOptions;
  if (Ctxt.Options * [woFullExpand, woHumanReadable, woEnumSetsAsText] <> []) or
     (o * [twoEnumSetsAsBooleanInRecord, twoEnumSetsAsTextInRecord] <> []) then
  begin
    PS := Ctxt.Info.Cache.EnumInfo^.GetEnumNameOrd(Data^);
    if twoEnumSetsAsBooleanInRecord in o then
      Ctxt.AddShortBoolean(PS, true)
    else
      Ctxt.AddShort(PS);
    if woHumanReadableEnumSetAsComment in Ctxt.Options then
      Ctxt.Info.Cache.EnumInfo^.GetEnumNameAll(Ctxt.W.fBlockComment, '', true);
  end
  else
    Ctxt.W.AddU(Data^);
end;

procedure _JS_Set(Data: PCardinal; const Ctxt: TJsonSaveContext);
var
  PS: PShortString;
  i: cardinal;
  v: QWord;
  o: TTextWriterOptions;
begin
  o := Ctxt.W.CustomOptions;
  if twoEnumSetsAsBooleanInRecord in o then
  begin
    // { "set1": true/false, .... } with proper indentation
    PS := Ctxt.Info.Cache.EnumList;
    Ctxt.W.BlockBegin('{', Ctxt.Options);
    i := 0;
    repeat
      Ctxt.AddShortBoolean(PS, GetBitPtr(Data, i));
      if i = Ctxt.Info.Cache.EnumMax then
        break;
      inc(i);
      Ctxt.W.BlockAfterItem(Ctxt.Options);
      inc(PByte(PS), PByte(PS)^ + 1); // next
    until false;
    Ctxt.W.BlockEnd('}', Ctxt.Options);
  end
  else if (Ctxt.Options * [woFullExpand, woHumanReadable, woEnumSetsAsText] <> []) or
          (twoEnumSetsAsTextInRecord in o) then
  begin
    // [ "set1", "set4", .... } on same line
    Ctxt.W.Add('[');
    if ((twoFullSetsAsStar in o) or
        (woHumanReadableFullSetsAsStar in Ctxt.Options)) and
       GetAllBits(Data^, Ctxt.Info.Cache.EnumMax + 1) then
      Ctxt.W.AddShorter('"*"')
    else
    begin
      PS := Ctxt.Info.Cache.EnumList;
      for i := 0 to Ctxt.Info.Cache.EnumMax do
      begin
        if GetBitPtr(Data, i) then
        begin
          Ctxt.W.Add('"');
          Ctxt.W.AddShort(PS^);
          Ctxt.W.Add('"', ',');
        end;
        inc(PByte(PS), PByte(PS)^ + 1); // next
      end;
      Ctxt.W.CancelLastComma;
    end;
    Ctxt.W.Add(']');
    if woHumanReadableEnumSetAsComment in Ctxt.Options then
      Ctxt.Info.Cache.EnumInfo^.GetEnumNameAll(
        Ctxt.W.fBlockComment, '"*" or a set of ', true);
  end
  else
  begin
    // standard serialization as unsigned integer (up to 64 items)
    v := 0;
    MoveSmall(Data, @v, Ctxt.Info.Size);
    Ctxt.W.AddQ(v);
  end;
end;

procedure _JS_Array(Data: PAnsiChar; const Ctxt: TJsonSaveContext);
var
  n: integer;
  jsonsave: TRttiJsonSave;
  c: TJsonSaveContext;
begin
  {%H-}c.Init(Ctxt.W, Ctxt.Options, Ctxt.Info.ArrayRtti);
  c.W.BlockBegin('[', c.Options);
  jsonsave := c.Info.JsonSave; // e.g. PT_JSONSAVE/PTC_JSONSAVE
  if Assigned(jsonsave) then
  begin
    // efficient JSON serialization
    n := Ctxt.Info.Cache.ItemCount;
    repeat
      jsonsave(Data, c);
      dec(n);
      if n = 0 then
        break;
      c.W.BlockAfterItem(c.Options);
      inc(Data, c.Info.Cache.Size);
    until false;
  end
  else
    // fallback to raw RTTI binary serialization with Base64 encoding
    c.W.BinarySaveBase64(Data, Ctxt.Info.Info, [rkArray],
      {withMagic=}true, {withcrc=}false);
  c.W.BlockEnd(']', c.Options);
end;

procedure _JS_DynArray_Custom(Data: pointer; const Ctxt: TJsonSaveContext);
begin
  // TRttiJson.RegisterCustomSerializer() custom callback for each item
  TOnRttiJsonWrite(TRttiJson(Ctxt.Info).fJsonWriter)(
    Ctxt.W, Data, Ctxt.Options);
end;

procedure _JS_DynArray(Data: PPointer; const Ctxt: TJsonSaveContext);
var
  n, s: PtrInt;
  jsonsave: TRttiJsonSave;
  P: PAnsiChar;
  c: TJsonSaveContext;
begin
  {%H-}c.Init(Ctxt.W, Ctxt.Options, Ctxt.Info.ArrayRtti);
  c.W.BlockBegin('[', c.Options);
  if Data^ <> nil then
  begin
    if TRttiJson(Ctxt.Info).fJsonWriter.Code <> nil then
    begin
      // TRttiJson.RegisterCustomSerializer() custom callbacks
      c.Info := Ctxt.Info;
      jsonsave := @_JS_DynArray_Custom;
    end
    else if c.Info = nil then
      jsonsave := nil
    else
      jsonsave := c.Info.JsonSave; // e.g. PT_JSONSAVE/PTC_JSONSAVE
    if Assigned(jsonsave) then
    begin
      // efficient JSON serialization
      P := Data^;
      n := PDALen(P - _DALEN)^ + _DAOFF; // length(Data)
      s := Ctxt.Info.Cache.ItemSize; // c.Info may be nil
      repeat
        jsonsave(P, c);
        dec(n);
        if n = 0 then
          break;
        c.W.BlockAfterItem(c.Options);
        inc(P, s);
      until false;
    end
    else
      // fallback to raw RTTI binary serialization with Base64 encoding
      c.W.BinarySaveBase64(Data, Ctxt.Info.Info, [rkDynArray],
        {withMagic=}true, {withcrc=}false);
  end
  else if (woHumanReadableEnumSetAsComment in Ctxt.Options) and
          (c.Info <> nil) and
          (rcfHasNestedProperties in c.Info.Flags) then
    // void dynarray should include record/T*ObjArray fields as comment
    c.Info.Props.AsText(c.W.fBlockComment, true, 'array of {', '}');
  c.W.BlockEnd(']', c.Options);
end;

const
  /// use pointer to allow any kind of Data^ type in above functions
  // - typecast to TRttiJsonSave for proper function call
  // - rkRecord and rkClass are handled in TRttiJson.SetParserType
  PT_JSONSAVE: array[TRttiParserType] of pointer = (
    nil, @_JS_Array, @_JS_Boolean, @_JS_Byte, @_JS_Cardinal, @_JS_Currency,
    @_JS_Double, @_JS_Extended, @_JS_Int64, @_JS_Integer, @_JS_QWord,
    @_JS_RawByteString, @_JS_RawJson, @_JS_RawUtf8, nil, @_JS_Single,
    {$ifdef UNICODE} @_JS_Unicode {$else} @_JS_RawUtf8 {$endif},
    @_JS_Unicode, @_JS_DateTime, @_JS_DateTimeMS, @_JS_GUID, @_JS_Hash,
    @_JS_Hash, @_JS_Hash, nil, @_JS_TimeLog, @_JS_Unicode, @_JS_UnixTime,
    @_JS_UnixMSTime, @_JS_Variant, @_JS_Unicode, @_JS_WinAnsi, @_JS_Word,
    @_JS_Enumeration, @_JS_Set, nil, @_JS_DynArray, @_JS_Interface, nil);

  /// use pointer to allow any complex kind of Data^ type in above functions
  // - typecast to TRttiJsonSave for proper function call
  PTC_JSONSAVE: array[TRttiParserComplexType] of pointer = (
    nil, nil, nil, nil, @_JS_ID, @_JS_ID, @_JS_QWord, @_JS_QWord, @_JS_QWord);

type
  TCCHook = class(TObjectWithCustomCreate); // to access its protected methods
  TCCHookClass = class of TCCHook;

procedure AppendExceptionLocation(w: TTextWriter; e: ESynException);
begin // call TDebugFile.FindLocationShort if mormot.core.log is used
  w.Add('"');
  w.AddShort(GetExecutableLocation(e.RaisedAt));
  w.Add('"');
end;

// serialization of published props for records and classes
procedure _JS_RttiCustom(Data: PAnsiChar; const Ctxt: TJsonSaveContext);
var
  nfo: TRttiJson;
  p: PRttiCustomProp;
  n: integer;
  done: boolean;
  c: TJsonSaveContext;
begin
  c.W := Ctxt.W;
  c.Options := Ctxt.Options;
  nfo := TRttiJson(Ctxt.Info);
  if (nfo.Kind = rkClass) and
     (Data <> nil) then
    // class instances are accessed by reference, records are stored by value
    Data := PPointer(Data)^
  else
    exclude(c.Options, woFullExpand); // not for null or for records
  if Data = nil then
    // append 'null' for nil class instance
    c.W.AddNull
  else if nfo.fJsonWriter.Code <> nil then
    // TRttiJson.RegisterCustomSerializer() custom callbacks
    TOnRttiJsonWrite(nfo.fJsonWriter)(c.W, Data, c.Options)
  else if not (rcfHookWrite in nfo.Flags) or
          not TCCHook(Data).RttiBeforeWriteObject(c.W, c.Options) then
  begin
    // regular JSON serialization using nested fields/properties
    c.W.BlockBegin('{', c.Options);
    c.Prop := pointer(nfo.Props.List);
    n := nfo.Props.Count;
    if (nfo.Kind = rkClass) and
       (c.Options * [woFullExpand, woStoreClassName, woStorePointer, woDontStoreInherited] <> []) then
    begin
      if woFullExpand in c.Options then
      begin
        c.W.AddInstanceName(TObject(Data), ':');
        c.W.BlockBegin('{', c.Options);
      end;
      if woStoreClassName in c.Options then
      begin
        c.W.WriteObjectPropNameShort('ClassName', c.Options);
        c.W.Add('"');
        c.W.AddShort(ClassNameShort(PClass(Data)^)^);
        c.W.Add('"');
        if (c.Prop <> nil) or
           (woStorePointer in c.Options) then
          c.W.BlockAfterItem(c.Options);
      end;
      if woStorePointer in c.Options then
      begin
        c.W.WriteObjectPropNameShort('Address', c.Options);
        if Ctxt.Info.ValueRtlClass = vcESynException then
          AppendExceptionLocation(c.W, ESynException(Data))
        else
          c.W.AddPointer(PtrUInt(Data), '"');
        if c.Prop <> nil then
          c.W.BlockAfterItem(c.Options);
      end;
      if woDontStoreInherited in c.Options then
        with Ctxt.Info.Props do
        begin
          // List[NotInheritedIndex]..List[Count-1] store the last hierarchy level
          n := Count - NotInheritedIndex;
          inc(c.Prop, NotInheritedIndex);
        end;
    end;
    done := false;
    if n > 0 then
      // this is the main loop serializing Info.Props[]
      repeat
        p := c.Prop;
        if // handle Props.NameChange() set to New='' to ignore this field
           (p^.Name <> '') and
           // handle woStoreStoredFalse flag and "stored" attribute in code
           ((woStoreStoredFalse in c.Options) or
            (rcfDisableStored in Ctxt.Info.Flags) or
            (p^.Prop = nil) or
            (p^.Prop.IsStored(pointer(Data)))) and
           // handle woDontStoreDefault flag over "default" attribute in code
           (not (woDontStoreDefault in c.Options) or
            (p^.Prop = nil) or
            (p^.OrdinalDefault = NO_DEFAULT) or
            not p^.ValueIsDefault(Data)) and
           // detect 0 numeric values and empty strings
           (not (woDontStoreVoid in c.Options) or
            not p^.ValueIsVoid(Data)) then
        begin
          // if we reached here, we should serialize this property
          if done then
            // append ',' and proper indentation if a field was just appended
            c.W.BlockAfterItem(c.Options);
          done := true;
          c.W.WriteObjectPropName(pointer(p^.Name), length(p^.Name), c.Options);
          if not (rcfHookWriteProperty in Ctxt.Info.Flags) or
             not TCCHook(Data).RttiWritePropertyValue(c.W, p, c.Options) then
            if (woHideSensitivePersonalInformation in c.Options) and
               (rcfSpi in p^.Value.Flags) then
              c.W.AddShorter('"***"')
            else if p^.OffsetGet >= 0 then
            begin
              // direct value write (record field or plain class property)
              c.Info := p^.Value;
              TRttiJsonSave(c.Info.JsonSave)(Data + p^.OffsetGet, c);
            end
            else
              // need to call a getter method
              p^.AddValueJson(c.W, Data, c.Options);
        end;
        dec(n);
        if n = 0 then
          break;
        inc(c.Prop);
      until false;
    if rcfHookWrite in Ctxt.Info.Flags then
       TCCHook(Data).RttiAfterWriteObject(c.W, c.Options);
    c.W.BlockEnd('}', c.Options);
    if woFullExpand in c.Options then
      c.W.BlockEnd('}', c.Options);
  end;
end;

// most known RTL classes custom serialization

procedure _JS_Objects(W: TTextWriter; Value: PObject; Count: integer;
  Options: TTextWriterWriteObjectOptions);
var
  ctxt: TJsonSaveContext;
  save: TRttiJsonSave;
  c, v: pointer; // reuse ctxt.Info if classes are the same (very likely)
begin
  c := nil;
  save := nil;
  {%H-}ctxt.Init(W, Options, nil);
  W.BlockBegin('[', Options);
  if Count > 0 then
    repeat
      v := Value^;
      if v = nil then
        W.AddNull
      else
      begin
        v := PPointer(v)^; // check Value class
        if v <> c then
        begin
          // need to retrieve the RTTI
          c := v;
          ctxt.Info := Rtti.RegisterClass(TClass(v));
          save := ctxt.Info.JsonSave;
        end;
        // this is where each object is serialized
        save(pointer(Value), ctxt);
      end;
      dec(Count);
      if Count = 0 then
        break;
      W.BlockAfterItem(Options);
      inc(Value);
    until false;
  W.BlockEnd(']', Options);
end;

procedure _JS_TList(Data: PList; const Ctxt: TJsonSaveContext);
begin
  if Data^ = nil then
    Ctxt.W.AddNull
  else
    _JS_Objects(Ctxt.W, pointer(Data^.List), Data^.Count, Ctxt.Options);
end;

procedure _JS_TObjectList(Data: PObjectList; const Ctxt: TJsonSaveContext);
var
  o: TTextWriterWriteObjectOptions;
begin
  if Data^ = nil then
  begin
    Ctxt.W.AddNull;
    exit;
  end;
  o := Ctxt.Options;
  if not (woObjectListWontStoreClassName in o) then
    include(o, woStoreClassName);
  _JS_Objects(Ctxt.W, pointer(Data^.List), Data^.Count, o);
end;

procedure _JS_TCollection(Data: PCollection; const Ctxt: TJsonSaveContext);
var
  item: TCollectionItem;
  i, last: PtrInt;
  c: TJsonSaveContext; // reuse same context for all collection items
begin
  if Data^ = nil then
  begin
    Ctxt.W.AddNull;
    exit;
  end;
  // can't use AddObjects() since we don't have access to the TCollection list
  {%H-}c.Init(Ctxt.W, Ctxt.Options, Rtti.RegisterClass(Data^.ItemClass));
  c.W.BlockBegin('[', c.Options);
  i := 0;
  last := Data^.Count - 1;
  if last >= 0 then
    repeat
      item := Data^.Items[i];
      TRttiJsonSave(c.Info.JsonSave)(@item, c);
      if i = last then
        break;
      c.W.BlockAfterItem(c.Options);
      inc(i);
    until false;
  c.W.BlockEnd(']', c.Options);
end;

procedure _JS_TStrings(Data: PStrings; const Ctxt: TJsonSaveContext);
var
  i, last: PtrInt;
begin
  if Data^ = nil then
  begin
    Ctxt.W.AddNull;
    exit;
  end;
  Ctxt.W.BlockBegin('[', Ctxt.Options);
  i := 0;
  last := Data^.Count - 1;
  if last >= 0 then
    repeat
      Ctxt.W.Add('"');
      Ctxt.W.AddJsonEscapeString(Data^.Strings[i]);
      Ctxt.W.Add('"');
      if i = last then
        break;
      Ctxt.W.BlockAfterItem(Ctxt.Options);
      inc(i);
    until false;
  Ctxt.W.BlockEnd(']', Ctxt.Options);
end;

procedure _JS_TRawUtf8List(Data: PRawUtf8List; const Ctxt: TJsonSaveContext);
var
  i, last: PtrInt;
  u: PPUtf8CharArray;
begin
  if Data^ = nil then
  begin
    Ctxt.W.AddNull;
    exit;
  end;
  Ctxt.W.BlockBegin('[', Ctxt.Options);
  i := 0;
  u := Data^.TextPtr;
  last := Data^.Count - 1;
  if last >= 0 then
    repeat
      Ctxt.W.Add('"');
      Ctxt.W.AddJsonEscape(u[i]);
      Ctxt.W.Add('"');
      if i = last then
        break;
      Ctxt.W.BlockAfterItem(Ctxt.Options);
      inc(i);
    until false;
  Ctxt.W.BlockEnd(']', Ctxt.Options);
end;

procedure _JS_TSynList(Data: PSynList; const Ctxt: TJsonSaveContext);
begin
  if Data^ = nil then
    Ctxt.W.AddNull
  else
    _JS_Objects(Ctxt.W, pointer(Data^.List), Data^.Count, Ctxt.Options);
end;

procedure _JS_TSynObjectList(Data: PSynObjectList; const Ctxt: TJsonSaveContext);
var
  o: TTextWriterWriteObjectOptions;
begin
  if Data^ = nil then
  begin
    Ctxt.W.AddNull;
    exit;
  end;
  o := Ctxt.Options;
  if not (woObjectListWontStoreClassName in o) then
    include(o, woStoreClassName);
  _JS_Objects(Ctxt.W, pointer(Data^.List), Data^.Count, o);
end;



{ ********** TTextWriter class with proper JSON escaping and WriteObject() support }

{ TTextWriter }

procedure TTextWriter.WriteObjectPropName(PropName: PUtf8Char;
  PropNameLen: PtrInt; Options: TTextWriterWriteObjectOptions);
begin
  if woHumanReadable in Options then
    AddCRAndIndent; // won't do anything if has already been done
  AddProp(PropName, PropNameLen); // handle twoForceJsonExtended
  if woHumanReadable in Options then
    Add(' ');
end;

procedure TTextWriter.WriteObjectPropNameShort(const PropName: shortstring;
  Options: TTextWriterWriteObjectOptions);
begin
  WriteObjectPropName(@PropName[1], ord(PropName[0]), Options);
end;

procedure TTextWriter.WriteObjectAsString(Value: TObject;
  Options: TTextWriterWriteObjectOptions);
begin
  Add('"');
  InternalJsonWriter.WriteObject(Value, Options);
  AddJsonEscape(fInternalJsonWriter);
  Add('"');
end;

procedure TTextWriter.AddDynArrayJsonAsString(aTypeInfo: PRttiInfo; var aValue;
  WriteOptions: TTextWriterWriteObjectOptions);
var
  temp: TDynArray;
begin
  Add('"');
  temp.Init(aTypeInfo, aValue);
  InternalJsonWriter.AddDynArrayJson(temp, WriteOptions);
  AddJsonEscape(fInternalJsonWriter);
  Add('"');
end;

procedure TTextWriter.BlockBegin(Starter: AnsiChar;
  Options: TTextWriterWriteObjectOptions);
begin
  if woHumanReadable in Options then
  begin
    AddCRAndIndent;
    inc(fHumanReadableLevel);
  end;
  Add(Starter);
end;

procedure TTextWriter.BlockEnd(Stopper: AnsiChar;
  Options: TTextWriterWriteObjectOptions);
begin
  if woHumanReadable in Options then
  begin
    dec(fHumanReadableLevel);
    AddCRAndIndent;
  end;
  Add(Stopper);
end;

procedure TTextWriter.AddCRAndIndent;
begin
  if fBlockComment <> '' then
  begin
    AddShorter(' // ');
    AddString(fBlockComment);
    fBlockComment := '';
  end;
  inherited AddCRAndIndent;
end;

procedure TTextWriter.AddPropJsonString(const PropName: shortstring;
  const Text: RawUtf8);
begin
  AddProp(@PropName[1], ord(PropName[0]));
  AddJsonString(Text);
  AddComma;
end;

procedure TTextWriter.AddPropJSONInt64(const PropName: shortstring;
  Value: Int64);
begin
  AddProp(@PropName[1], ord(PropName[0]));
  Add(Value);
  AddComma;
end;

procedure TTextWriter.InternalAddFixedAnsi(Source: PAnsiChar; SourceChars: cardinal;
  AnsiToWide: PWordArray; Escape: TTextWriterKind);
var
  c: cardinal;
  esc: byte;
begin
  if SourceChars > 0 then
  repeat
    case Escape of // twJsonEscape or twOnSameLine only occur on c <= $7f
      twNone:
        repeat
          if B >= BEnd then
            FlushToStream;
          c := byte(Source^);
          inc(Source);
          if c > $7F then
             break;
          if c = 0 then
            exit;
          inc(B);
          B^ := AnsiChar(c);
          dec(SourceChars);
          if SourceChars = 0 then
            exit;
        until false;
      twJsonEscape:
        repeat
          if B >= BEnd then
            FlushToStream;
          c := byte(Source^);
          inc(Source);
          if c > $7F then
             break;
          if c = 0 then
            exit;
          esc := JSON_ESCAPE[c]; // c<>0 -> esc<>JSON_ESCAPE_ENDINGZERO
          if esc = JSON_ESCAPE_NONE then
          begin
            // no escape needed
            inc(B);
            B^ := AnsiChar(c);
          end
          else if esc = JSON_ESCAPE_UNICODEHEX then
          begin
            // characters below ' ', #7 e.g. -> \u0007
            AddShorter('\u00');
            AddByteToHex(c);
          end
          else
            Add('\', AnsiChar(esc)); // escaped as \ + b,t,n,f,r,\,"
          dec(SourceChars);
          if SourceChars = 0 then
            exit;
        until false;
    else  //twOnSameLine:
      repeat
        if B >= BEnd then
          FlushToStream;
        c := byte(Source^);
        inc(Source);
        if c > $7F then
           break;
        if c = 0 then
          exit;
        inc(B);
        if c < 32 then
          B^ := ' '
        else
          B^ := AnsiChar(c);
        dec(SourceChars);
        if SourceChars = 0 then
          exit;
      until false;
    end;
    // handle c > $7F (no surrogate is expected in TSynAnsiFixedWidth charsets)
    c := AnsiToWide[c]; // convert FixedAnsi char into Unicode char
    if c > $7ff then
    begin
      B[1] := AnsiChar($E0 or (c shr 12));
      B[2] := AnsiChar($80 or ((c shr 6) and $3F));
      B[3] := AnsiChar($80 or (c and $3F));
      inc(B, 3);
    end
    else
    begin
      B[1] := AnsiChar($C0 or (c shr 6));
      B[2] := AnsiChar($80 or (c and $3F));
      inc(B, 2);
    end;
    dec(SourceChars);
  until SourceChars = 0;
end;

destructor TTextWriter.Destroy;
begin
  inherited Destroy;
  fInternalJsonWriter.Free;
end;

function TTextWriter.InternalJsonWriter: TTextWriter;
begin
  if fInternalJsonWriter = nil then
    fInternalJsonWriter := TTextWriter.CreateOwnedStream
  else
    fInternalJsonWriter.CancelAll;
  result := fInternalJsonWriter;
end;

procedure TTextWriter.Add(P: PUtf8Char; Escape: TTextWriterKind);
begin
  if P <> nil then
    case Escape of
      twNone:
        AddNoJsonEscape(P, StrLen(P));
      twJsonEscape:
        AddJsonEscape(P);
      twOnSameLine:
        AddOnSameLine(P);
    end;
end;

procedure TTextWriter.Add(P: PUtf8Char; Len: PtrInt; Escape: TTextWriterKind);
begin
  if P <> nil then
    case Escape of
      twNone:
        AddNoJsonEscape(P, Len);
      twJsonEscape:
        AddJsonEscape(P, Len);
      twOnSameLine:
        AddOnSameLine(P, Len);
    end;
end;

procedure TTextWriter.AddW(P: PWord; Len: PtrInt; Escape: TTextWriterKind);
begin
  if P <> nil then
    case Escape of
      twNone:
        AddNoJsonEscapeW(P, Len);
      twJsonEscape:
        AddJsonEScapeW(P, Len);
      twOnSameLine:
        AddOnSameLineW(P, Len);
    end;
end;

procedure TTextWriter.AddAnsiString(const s: AnsiString; Escape: TTextWriterKind);
begin
  AddAnyAnsiBuffer(pointer(s), length(s), Escape, 0);
end;

procedure TTextWriter.AddAnyAnsiString(const s: RawByteString;
  Escape: TTextWriterKind; CodePage: integer);
var
  L: integer;
begin
  L := length(s);
  if L = 0 then
    exit;
  if (L > 2) and
     (PInteger(s)^ and $ffffff = JSON_BASE64_MAGIC_C) then
  begin
    AddNoJsonEscape(pointer(s), L); // was marked as a BLOB content
    exit;
  end;
  if CodePage < 0 then
    {$ifdef HASCODEPAGE}
    CodePage := StringCodePage(s);
    {$else}
    CodePage := 0; // TSynAnsiConvert.Engine(0)=CurrentAnsiConvert
    {$endif HASCODEPAGE}
  AddAnyAnsiBuffer(pointer(s), L, Escape, CodePage);
end;

procedure EngineAppendUtf8(W: TTextWriter; Engine: TSynAnsiConvert;
  P: PAnsiChar; Len: PtrInt; Escape: TTextWriterKind);
var
  tmp: TSynTempBuffer;
begin
  // explicit conversion using a temporary UTF-16 buffer on stack
  Engine.AnsiBufferToUnicode(tmp.Init(Len * 3), P, Len); // includes ending #0
  W.AddW(tmp.buf, 0, Escape);
  tmp.Done;
end;

procedure TTextWriter.AddAnyAnsiBuffer(P: PAnsiChar; Len: PtrInt;
  Escape: TTextWriterKind; CodePage: integer);
var
  B: PUtf8Char;
  engine: TSynAnsiConvert;
label
  utf8;
begin
  if Len > 0 then
  begin
    if CodePage = 0 then // CP_UTF8 is very likely on POSIX or LCL
      CodePage := Unicode_CodePage; // = CurrentAnsiConvert.CodePage
    case CodePage of
      CP_UTF8:          // direct write of RawUtf8 content
        begin
          if Escape = twJsonEscape then
            Len := 0;    // faster with no Len
utf8:     Add(PUtf8Char(P), Len, Escape);
        end;
      CP_RAWBYTESTRING: // direct write of RawByteString content
        goto utf8;
      CP_UTF16:         // direct write of UTF-16 content
        AddW(PWord(P), 0, Escape);
      CP_RAWBLOB:       // RawBlob written with Base-64 encoding
        begin
          AddShorter(JSON_BASE64_MAGIC_S); // \uFFF0
          WrBase64(P, Len, {withMagic=}false);
        end;
    else
      begin
        // first handle trailing 7-bit ASCII chars, by quad
        B := pointer(P);
        if Len >= 4 then
          repeat
            if PCardinal(P)^ and $80808080 <> 0 then
              break; // break on first non ASCII quad
            inc(P, 4);
            dec(Len, 4);
          until Len < 4;
        if (Len > 0) and
           (P^ < #128) then
          repeat
            inc(P);
            dec(Len);
          until (Len = 0) or
                (P^ >= #127);
        if P <> pointer(B) then
          Add(B, P - B, Escape);
        if Len <= 0 then
          exit;
        // rely on explicit conversion for all remaining ASCII characters
        engine := TSynAnsiConvert.Engine(CodePage);
        if PClass(engine)^ = TSynAnsiFixedWidth then
          InternalAddFixedAnsi(P, Len,
            pointer(TSynAnsiFixedWidth(engine).AnsiToWide), Escape)
        else
          EngineAppendUtf8(self, engine, P, Len, Escape);
      end;
    end;
  end;
end;

procedure TTextWriter.WrBase64(P: PAnsiChar; Len: PtrUInt; withMagic: boolean);
var
  trailing, main, n: PtrUInt;
begin
  if withMagic then
    if Len <= 0 then
    begin
      AddNull; // JSON null is better than "" for BLOBs
      exit;
    end
    else
      AddShorter(JSON_BASE64_MAGIC_QUOTE_S); // "\uFFF0
  if Len > 0 then
  begin
    n := Len div 3;
    trailing := Len - n * 3;
    dec(Len, trailing);
    if BEnd - B > integer(n + 1) shl 2 then
    begin
      // will fit in available space in Buf -> fast in-buffer Base64 encoding
      n := Base64EncodeMain(@B[1], P, Len);
      inc(B, n * 4);
      inc(P, n * 3);
    end
    else
    begin
      // bigger than available space in Buf -> do it per chunk
      FlushToStream;
      while Len > 0 do
      begin
        // length(buf) const -> so is ((length(buf)-4)shr2 )*3
        n := ((fTempBufSize - 4) shr 2) * 3;
        if Len < n then
          n := Len;
        main := Base64EncodeMain(PAnsiChar(fTempBuf), P, n);
        n := main * 4;
        if n < cardinal(fTempBufSize) - 4 then
          inc(B, n)
        else
          WriteToStream(fTempBuf, n);
        n := main * 3;
        inc(P, n);
        dec(Len, n);
      end;
    end;
    if trailing > 0 then
    begin
      Base64EncodeTrailing(@B[1], P, trailing);
      inc(B, 4);
    end;
  end;
  if withMagic then
    Add('"');
end;

procedure TTextWriter.BinarySaveBase64(Data: pointer; Info: PRttiInfo;
  Kinds: TRttiKinds; withMagic, withCrc: boolean);
var
  temp: TSynTempBuffer;
begin
  BinarySave(Data, temp, Info, Kinds, withCrc);
  WrBase64(temp.buf, temp.len, withMagic);
  temp.Done;
end;

procedure TTextWriter.Add(const Format: RawUtf8; const Values: array of const;
  Escape: TTextWriterKind; WriteObjectOptions: TTextWriterWriteObjectOptions);
var
  ValuesIndex: integer;
  S, F: PUtf8Char;
begin
  if Format = '' then
    exit;
  if (Format = '%') and
     (high(Values) >= 0) then
  begin
    Add(Values[0], Escape);
    exit;
  end;
  ValuesIndex := 0;
  F := pointer(Format);
  repeat
    S := F;
    repeat
      if (F^ = #0) or
         (F^ = '%') then
        break;
      inc(F);
    until false;
    AddNoJsonEscape(S, F - S);
    if F^ = #0 then
      exit;
    // add next value as text instead of F^='%' placeholder
    if ValuesIndex <= high(Values) then // missing value will display nothing
      Add(Values[ValuesIndex], Escape, WriteObjectOptions);
    inc(F);
    inc(ValuesIndex);
  until false;
end;

procedure TTextWriter.AddTimeLog(Value: PInt64; QuoteChar: AnsiChar);
begin
  if BEnd - B <= 31 then
    FlushToStream;
  B := PTimeLogBits(Value)^.Text(B + 1, true, 'T', QuoteChar) - 1;
end;

procedure TTextWriter.AddUnixTime(Value: PInt64; QuoteChar: AnsiChar);
var
  DT: TDateTime;
begin
  // inlined UnixTimeToDateTime()
  DT := Value^ / SecsPerDay + UnixDateDelta;
  AddDateTime(@DT, 'T', QuoteChar, {withms=}false, {dateandtime=}true);
end;

procedure TTextWriter.AddUnixMSTime(Value: PInt64; WithMS: boolean;
  QuoteChar: AnsiChar);
var
  DT: TDateTime;
begin
  // inlined UnixMSTimeToDateTime()
  DT := Value^ / MSecsPerDay + UnixDateDelta;
  AddDateTime(@DT, 'T', QuoteChar, WithMS, {dateandtime=}true);
end;

procedure TTextWriter.AddDateTime(Value: PDateTime; FirstChar: AnsiChar;
  QuoteChar: AnsiChar; WithMS: boolean; AlwaysDateAndTime: boolean);
var
  T: TSynSystemTime;
begin
  if (Value^ = 0) and
     (QuoteChar = #0) then
    exit;
  if BEnd - B <= 25 then
    FlushToStream;
  inc(B);
  if QuoteChar <> #0 then
    B^ := QuoteChar
  else
    dec(B);
  if Value^ <> 0 then
  begin
    inc(B);
    if AlwaysDateAndTime or
       (trunc(Value^) <> 0) then
    begin
      T.FromDate(Value^);
      B := DateToIso8601PChar(B, true, T.Year, T.Month, T.Day);
    end;
    if AlwaysDateAndTime or
       (frac(Value^) <> 0) then
    begin
      T.FromTime(Value^);
      B := TimeToIso8601PChar(B, true, T.Hour, T.Minute, T.Second,
        T.MilliSecond, FirstChar, WithMS);
    end;
    dec(B);
  end;
  if QuoteChar <> #0 then
  begin
    inc(B);
    B^ := QuoteChar;
  end;
end;

procedure TTextWriter.AddDateTime(const Value: TDateTime; WithMS: boolean);
begin
  if Value = 0 then
    exit;
  if BEnd - B <= 23 then
    FlushToStream;
  inc(B);
  if trunc(Value) <> 0 then
    B := DateToIso8601PChar(Value, B, true);
  if frac(Value) <> 0 then
    B := TimeToIso8601PChar(Value, B, true, 'T', WithMS);
  dec(B);
end;

procedure TTextWriter.AddDateTimeMS(const Value: TDateTime; Expanded: boolean;
  FirstTimeChar: AnsiChar; const TZD: RawUtf8);
var
  T: TSynSystemTime;
begin
  if Value = 0 then
    exit;
  T.FromDateTime(Value);
  Add(DTMS_FMT[Expanded], [UInt4DigitsToShort(T.Year), UInt2DigitsToShortFast(T.Month),
    UInt2DigitsToShortFast(T.Day), FirstTimeChar, UInt2DigitsToShortFast(T.Hour),
    UInt2DigitsToShortFast(T.Minute), UInt2DigitsToShortFast(T.Second),
    UInt3DigitsToShort(T.MilliSecond), TZD]);
end;

procedure TTextWriter.AddCurrentLogTime(LocalTime: boolean);
var
  time: TSynSystemTime;
begin
  time.FromNow(LocalTime);
  time.AddLogTime(self);
end;

procedure TTextWriter.AddCurrentNCSALogTime(LocalTime: boolean);
var
  time: TSynSystemTime;
begin
  time.FromNow(LocalTime);
  if BEnd - B <= 21 then
    FlushToStream;
  inc(B, time.ToNCSAText(B + 1));
end;

procedure TTextWriter.AddCsvInteger(const Integers: array of integer);
var
  i: PtrInt;
begin
  if length(Integers) = 0 then
    exit;
  for i := 0 to high(Integers) do
  begin
    Add(Integers[i]);
    AddComma;
  end;
  CancelLastComma;
end;

procedure TTextWriter.AddCsvDouble(const Doubles: array of double);
var
  i: PtrInt;
begin
  if length(Doubles) = 0 then
    exit;
  for i := 0 to high(Doubles) do
  begin
    AddDouble(Doubles[i]);
    AddComma;
  end;
  CancelLastComma;
end;

procedure TTextWriter.AddCsvUtf8(const Values: array of RawUtf8);
var
  i: PtrInt;
begin
  if length(Values) = 0 then
    exit;
  for i := 0 to high(Values) do
  begin
    Add('"');
    AddJsonEscape(pointer(Values[i]));
    Add('"', ',');
  end;
  CancelLastComma;
end;

procedure TTextWriter.AddCsvConst(const Values: array of const);
var
  i: PtrInt;
begin
  if length(Values) = 0 then
    exit;
  for i := 0 to high(Values) do
  begin
    AddJsonEscape(Values[i]);
    AddComma;
  end;
  CancelLastComma;
end;

procedure TTextWriter.Add(const Values: array of const);
var
  i: PtrInt;
begin
  for i := 0 to high(Values) do
    AddJsonEscape(Values[i]);
end;

procedure TTextWriter.AddQuotedStringAsJson(const QuotedString: RawUtf8);
var
  L: integer;
  P, B: PUtf8Char;
  quote: AnsiChar;
begin
  L := length(QuotedString);
  if L > 0 then
  begin
    quote := QuotedString[1];
    if (quote in ['''', '"']) and
       (QuotedString[L] = quote) then
    begin
      Add('"');
      P := pointer(QuotedString);
      inc(P);
      repeat
        B := P;
        while P[0] <> quote do
          inc(P);
        if P[1] <> quote then
          break; // end quote
        inc(P);
        AddJsonEscape(B, P - B);
        inc(P); // ignore double quote
      until false;
      if P - B <> 0 then
        AddJsonEscape(B, P - B);
      Add('"');
    end
    else
      AddNoJsonEscape(pointer(QuotedString), length(QuotedString));
  end;
end;

procedure TTextWriter.AddVariant(const Value: variant; Escape: TTextWriterKind;
  WriteOptions: TTextWriterWriteObjectOptions);
var
  cv: TSynInvokeableVariantType;
  v: TVarData absolute Value;
  vt: cardinal;
begin
  vt := v.VType;
  case vt of
    varEmpty, varNull:
      AddNull;
    varSmallint:
      Add(v.VSmallint);
    varShortInt:
      Add(v.VShortInt);
    varByte:
      AddU(v.VByte);
    varWord:
      AddU(v.VWord);
    varLongWord:
      AddU(v.VLongWord);
    varInteger:
      Add(v.VInteger);
    varInt64:
      Add(v.VInt64);
    varWord64:
      AddQ(v.VInt64);
    varSingle:
      AddSingle(v.VSingle);
    varDouble:
      AddDouble(v.VDouble);
    varDate:
      AddDateTime(@v.VDate, 'T', '"');
    varCurrency:
      AddCurr64(@v.VInt64);
    varBoolean:
      Add(v.VBoolean); // 'true'/'false'
    varVariant:
      AddVariant(PVariant(v.VPointer)^, Escape, WriteOptions);
    varString:
      AddText(RawByteString(v.VString), Escape);
    varOleStr {$ifdef HASVARUSTRING}, varUString{$endif}:
      AddTextW(v.VAny, Escape);
    varAny:
      // rkEnumeration,rkSet,rkDynArray,rkClass,rkInterface,rkRecord,rkObject
      // from TRttiCustomProp.GetValueDirect/GetValueGetter
      AddRttiVarData(TRttiVarData(V), WriteOptions);
    varVariantByRef:
      AddVariant(PVariant(v.VPointer)^, Escape, WriteOptions);
    varStringByRef:
      AddText(PRawByteString(v.VAny)^, Escape);
    {$ifdef HASVARUSTRING} varUStringByRef, {$endif}
    varOleStrByRef:
      AddTextW(PPointer(v.VAny)^, Escape)
  else
    if vt >= varArray then // complex types are always < varArray
      AddNull
    else if DocVariantType.FindSynVariantType(vt, cv) then // our custom types
      cv.ToJson(self, Value, Escape)
    else if not CustomVariantToJson(self, Value, Escape) then // generic CastTo
      raise EJsonException.CreateUtf8('%.AddVariant VType=%', [self, vt]);
  end;
end;

procedure TTextWriter.AddTypedJson(Value, TypeInfo: pointer;
  WriteOptions: TTextWriterWriteObjectOptions);
var
  ctxt: TJsonSaveContext;
  save: TRttiJsonSave;
begin
  {%H-}ctxt.Init(self, WriteOptions, Rtti.RegisterType(TypeInfo));
  if ctxt.Info = nil then
    AddNull // paranoid check
  else
  begin
    save := ctxt.Info.JsonSave;
    if Assigned(save) then
      save(Value, ctxt)
    else
      BinarySaveBase64(Value, TypeInfo, rkRecordTypes, {withMagic=}true);
  end;
end;

procedure TTextWriter.WriteObject(Value: TObject;
  WriteOptions: TTextWriterWriteObjectOptions);
var
  ctxt: TJsonSaveContext;
  save: TRttiJsonSave;
begin
  if Value <> nil then
  begin
    // Rtti.RegisterClass() may create fake RTTI if {$M+} was not used
    {%H-}ctxt.Init(self, WriteOptions, Rtti.RegisterClass(PClass(Value)^));
    save := ctxt.Info.JsonSave;
    if Assigned(save) then
    begin
      save(@Value, ctxt);
      exit;
    end;
  end;
  AddNull;
end;

procedure TTextWriter.AddRttiCustomJson(Value: pointer; RttiCustom: TObject;
  WriteOptions: TTextWriterWriteObjectOptions);
var
  ctxt: TJsonSaveContext;
  save: TRttiJsonSave;
begin
  {%H-}ctxt.Init(self, WriteOptions, TRttiCustom(RttiCustom));
  save := ctxt.Info.JsonSave;
  if Assigned(save) then
    save(Value, ctxt)
  else
    BinarySaveBase64(Value, ctxt.Info.Info, rkAllTypes, {magic=}true);
end;

procedure TTextWriter.AddRttiVarData(const Value: TRttiVarData;
  WriteOptions: TTextWriterWriteObjectOptions);
var
  V64: Int64;
begin
  if Value.PropValueIsInstance then
  begin
    // from TRttiCustomProp.GetValueGetter
    if rcfGetOrdProp in Value.Prop.Value.Cache.Flags then
    begin
      // rkEnumeration,rkSet,rkDynArray,rkClass,rkInterface
      V64 := Value.Prop.Prop.GetOrdProp(Value.PropValue);
      AddRttiCustomJson(@V64, Value.Prop.Value, WriteOptions);
    end
    else
      // rkRecord,rkObject have no getter methods
      raise EJsonException.CreateUtf8('%.AddRttiVarData: unsupported % (%)',
        [self, Value.Prop.Value.Name, ToText(Value.Prop.Value.Kind)^]);
  end
  else
    // from TRttiCustomProp.GetValueDirect
    AddRttiCustomJson(Value.PropValue, Value.Prop.Value, WriteOptions);
end;

procedure TTextWriter.AddText(const Text: RawByteString; Escape: TTextWriterKind);
begin
  if Escape = twJsonEscape then
    Add('"');
  {$ifdef HASCODEPAGE}
  AddAnyAnsiString(Text, Escape);
  {$else}
  Add(pointer(Text), length(Text), Escape);
  {$endif HASCODEPAGE}
  if Escape = twJsonEscape then
    Add('"');
end;

procedure TTextWriter.AddTextW(P: PWord; Escape: TTextWriterKind);
begin
  if Escape = twJsonEscape then
    Add('"');
  AddW(P, 0, Escape);
  if Escape = twJsonEscape then
    Add('"');
end;

function TTextWriter.AddJsonReformat(Json: PUtf8Char; Format: TTextWriterJsonFormat;
 EndOfObject: PUtf8Char): PUtf8Char;
var
  objEnd: AnsiChar;
  Name, Value: PUtf8Char;
  NameLen: integer;
  ValueLen: PtrInt;
  tab: PJsonCharSet;
begin
  result := nil;
  if Json = nil then
    exit;
  while (Json^ <= ' ') and
        (Json^ <> #0) do
    inc(Json);
  case Json^ of
    '[':
      begin
        // array
        repeat
          inc(Json)
        until (Json^ = #0) or
              (Json^ > ' ');
        if Json^ = ']' then
        begin
          Add('[');
          inc(Json);
        end
        else
        begin
          if not (Format in [jsonCompact, jsonUnquotedPropNameCompact]) then
            AddCRAndIndent;
          inc(fHumanReadableLevel);
          Add('[');
          repeat
            if Json = nil then
              exit;
            if not (Format in [jsonCompact, jsonUnquotedPropNameCompact]) then
              AddCRAndIndent;
            Json := AddJsonReformat(Json, Format, @objEnd);
            if objEnd = ']' then
              break;
            Add(objEnd);
          until false;
          dec(fHumanReadableLevel);
          if not (Format in [jsonCompact, jsonUnquotedPropNameCompact]) then
            AddCRAndIndent;
        end;
        Add(']');
      end;
    '{':
      begin
        // object
        repeat
          inc(Json)
        until (Json^ = #0) or
              (Json^ > ' ');
        Add('{');
        inc(fHumanReadableLevel);
        if not (Format in [jsonCompact, jsonUnquotedPropNameCompact]) then
          AddCRAndIndent;
        if Json^ = '}' then
          repeat
            inc(Json)
          until (Json^ = #0) or
                (Json^ > ' ')
        else
          repeat
            Name := GetJsonPropName(Json, @NameLen);
            if Name = nil then
              exit;
            if (Format in [jsonUnquotedPropName, jsonUnquotedPropNameCompact]) and
               JsonPropNameValid(Name) then
              AddNoJsonEscape(Name, NameLen)
            else
            begin
              Add('"');
              AddJsonEscape(Name);
              Add('"');
            end;
            if Format in [jsonCompact, jsonUnquotedPropNameCompact] then
              Add(':')
            else
              Add(':', ' ');
            while (Json^ <= ' ') and
                  (Json^ <> #0) do
              inc(Json);
            Json := AddJsonReformat(Json, Format, @objEnd);
            if objEnd = '}' then
              break;
            Add(objEnd);
            if not (Format in [jsonCompact, jsonUnquotedPropNameCompact]) then
              AddCRAndIndent;
          until false;
        dec(fHumanReadableLevel);
        if not (Format in [jsonCompact, jsonUnquotedPropNameCompact]) then
          AddCRAndIndent;
        Add('}');
      end;
    '"':
      begin
        // string
        Value := Json;
        Json := GotoEndOfJsonString2(Json + 1, @JSON_CHARS);
        if Json^ <> '"' then
          exit;
        inc(Json);
        AddNoJsonEscape(Value, Json - Value);
      end;
  else
    begin
      // numeric value or true/false/null constant or MongoDB extended
      tab := @JSON_CHARS;
      if jcEndOfJsonFieldOr0 in tab[Json^] then
        exit; // #0 , ] } :
      Value := Json;
      ValueLen := 0;
      repeat
        inc(ValueLen);
      until jcEndOfJsonFieldOr0 in tab[Json[ValueLen]];
      inc(Json, ValueLen);
      while (ValueLen > 0) and
            (Value[ValueLen - 1] <= ' ') do
        dec(ValueLen);
      AddNoJsonEscape(Value, ValueLen);
    end;
  end;
  if Json = nil then
    exit;
  while (Json^ <= ' ') and
        (Json^ <> #0) do
    inc(Json);
  if EndOfObject <> nil then
    EndOfObject^ := Json^;
  if Json^ <> #0 then
    repeat
      inc(Json)
    until (Json^ = #0) or
          (Json^ > ' ');
  result := Json;
end;

function TTextWriter.AddJsonToXML(Json: PUtf8Char;
  ArrayName, EndOfObject: PUtf8Char): PUtf8Char;
var
  objEnd: AnsiChar;
  Name, Value: PUtf8Char;
  n, c: integer;
begin
  result := nil;
  if Json = nil then
    exit;
  while (Json^ <= ' ') and
        (Json^ <> #0) do
    inc(Json);
  case Json^ of
  '[':
    begin
      repeat
        inc(Json);
      until (Json^ = #0) or
            (Json^ > ' ');
      if Json^ = ']' then
        Json := GotoNextNotSpace(Json + 1)
      else
      begin
        n := 0;
        repeat
          if Json = nil then
            exit;
          Add('<');
          if ArrayName = nil then
            Add(n)
          else
            AddXmlEscape(ArrayName);
          Add('>');
          Json := AddJsonToXML(Json, nil, @objEnd);
          Add('<', '/');
          if ArrayName = nil then
            Add(n)
          else
            AddXmlEscape(ArrayName);
          Add('>');
          inc(n);
        until objEnd = ']';
      end;
    end;
  '{':
    begin
      repeat
        inc(Json);
      until (Json^ = #0) or
            (Json^ > ' ');
      if Json^ = '}' then
        Json := GotoNextNotSpace(Json + 1)
      else
      begin
        repeat
          Name := GetJsonPropName(Json);
          if Name = nil then
            exit;
          while (Json^ <= ' ') and
                (Json^ <> #0) do
            inc(Json);
          if Json^ = '[' then // arrays are written as list of items, without root
            Json := AddJsonToXML(Json, Name, @objEnd)
          else
          begin
            Add('<');
            AddXmlEscape(Name);
            Add('>');
            Json := AddJsonToXML(Json, Name, @objEnd);
            Add('<', '/');
            AddXmlEscape(Name);
            Add('>');
          end;
        until objEnd = '}';
      end;
    end;
  else
    begin
      Value := GetJsonField(Json, result, nil, EndOfObject); // let wasString=nil
      if Value = nil then
        AddNull
      else
      begin
        c := PInteger(Value)^ and $ffffff;
        if (c = JSON_BASE64_MAGIC_C) or
           (c = JSON_SQLDATE_MAGIC_C) then
          inc(Value, 3); // just ignore the Magic codepoint encoded as UTF-8
        AddXmlEscape(Value);
      end;
      exit;
    end;
  end;
  if Json <> nil then
  begin
    while (Json^ <= ' ') and
          (Json^ <> #0) do
      inc(Json);
    if EndOfObject <> nil then
      EndOfObject^ := Json^;
    if Json^ <> #0 then
      repeat
        inc(Json);
      until (Json^ = #0) or
            (Json^ > ' ');
  end;
  result := Json;
end;

procedure TTextWriter.AddJsonEscape(P: Pointer; Len: PtrInt);
var
  i, start: PtrInt;
  {$ifdef CPUX86NOTPIC}
  tab: TNormTableByte absolute JSON_ESCAPE;
  {$else}
  tab: PByteArray;
  {$endif CPUX86NOTPIC}
label
  noesc;
begin
  if P = nil then
    exit;
  if Len = 0 then
    dec(Len); // -1 = no end = AddJsonEscape(P, 0)
  i := 0;
  {$ifndef CPUX86NOTPIC}
  tab := @JSON_ESCAPE;
  {$endif CPUX86NOTPIC}
  if tab[PByteArray(P)[i]] = JSON_ESCAPE_NONE then
  begin
noesc:
    start := i;
    if Len < 0 then  // fastest loop is with AddJsonEscape(P, 0)
      repeat
        inc(i);
      until tab[PByteArray(P)[i]] <> JSON_ESCAPE_NONE
    else
      repeat
        inc(i);
      until (i >= Len) or
            (tab[PByteArray(P)[i]] <> JSON_ESCAPE_NONE);
    inc(PByte(P), start);
    dec(i, start);
    if Len >= 0 then
      dec(Len, start);
    if BEnd - B <= i then
      AddNoJsonEscape(P, i)
    else
    begin
      MoveFast(P^, B[1], i);
      inc(B, i);
    end;
    if (Len >= 0) and
       (i >= Len) then
      exit;
  end;
  repeat
    if B >= BEnd then
      FlushToStream;
    case tab[PByteArray(P)[i]] of // better codegen with no temp var
      JSON_ESCAPE_NONE:
        goto noesc;
      JSON_ESCAPE_ENDINGZERO:
        // #0
        exit;
      JSON_ESCAPE_UNICODEHEX:
        begin
          // characters below ' ', #7 e.g. -> // 'u0007'
          PCardinal(B + 1)^ :=
            ord('\') + ord('u') shl 8 + ord('0') shl 16 + ord('0') shl 24;
          inc(B, 4);
          PWord(B + 1)^ := TwoDigitsHexWB[PByteArray(P)[i]];
        end;
    else
      // escaped as \ + b,t,n,f,r,\,"
      PWord(B + 1)^ := (integer(tab[PByteArray(P)[i]]) shl 8) or ord('\');
    end;
    inc(i);
    inc(B, 2);
  until (Len >= 0) and
        (i >= Len);
end;

procedure TTextWriter.AddJsonEscapeString(const s: string);
begin
  if s <> '' then
    {$ifdef UNICODE}
    AddJsonEscapeW(pointer(s), Length(s));
    {$else}
    AddAnyAnsiString(s, twJsonEscape, 0);
    {$endif UNICODE}
end;

procedure TTextWriter.AddJsonEscapeAnsiString(const s: AnsiString);
begin
  AddAnyAnsiString(s, twJsonEscape, 0);
end;

procedure TTextWriter.AddJsonEscapeW(P: PWord; Len: PtrInt);
var
  i, c, s: PtrInt;
  esc: byte;
  tab: PByteArray;
begin
  if P = nil then
    exit;
  if Len = 0 then
    Len := MaxInt;
  i := 0;
  while i < Len do
  begin
    s := i;
    tab := @JSON_ESCAPE;
    repeat
      c := PWordArray(P)[i];
      if (c <= 127) and
         (tab[c] <> JSON_ESCAPE_NONE) then
        break;
      inc(i);
    until i >= Len;
    if i <> s then
      AddNoJsonEscapeW(@PWordArray(P)[s], i - s);
    if i >= Len then
      exit;
    c := PWordArray(P)[i];
    if c = 0 then
      exit;
    esc := tab[c];
    if esc = JSON_ESCAPE_ENDINGZERO then // #0
      exit
    else if esc = JSON_ESCAPE_UNICODEHEX then
    begin
      // characters below ' ', #7 e.g. -> \u0007
      AddShorter('\u00');
      AddByteToHex(c);
    end
    else
      Add('\', AnsiChar(esc)); // escaped as \ + b,t,n,f,r,\,"
    inc(i);
  end;
end;

procedure TTextWriter.AddJsonEscape(const V: TVarRec);
begin
  with V do
    case VType of
      vtPointer:
        AddNull;
      vtString, vtAnsiString, {$ifdef HASVARUSTRING}vtUnicodeString, {$endif}
      vtPChar, vtChar, vtWideChar, vtWideString, vtClass:
        begin
          Add('"');
          case VType of
            vtString:
              if (VString <> nil) and
                 (VString^[0] <> #0) then
                AddJsonEscape(@VString^[1], ord(VString^[0]));
            vtAnsiString:
              AddJsonEscape(VAnsiString);
            {$ifdef HASVARUSTRING}
            vtUnicodeString:
              AddJsonEscapeW(pointer(UnicodeString(VUnicodeString)),
                length(UnicodeString(VUnicodeString)));
            {$endif HASVARUSTRING}
            vtPChar:
              AddJsonEscape(VPChar);
            vtChar:
              AddJsonEscape(@VChar, 1);
            vtWideChar:
              AddJsonEscapeW(@VWideChar, 1);
            vtWideString:
              AddJsonEscapeW(VWideString);
            vtClass:
              AddClassName(VClass);
          end;
          Add('"');
        end;
      vtBoolean:
        Add(VBoolean); // 'true'/'false'
      vtInteger:
        Add(VInteger);
      vtInt64:
        Add(VInt64^);
      {$ifdef FPC}
      vtQWord:
        AddQ(V.VQWord^);
      {$endif FPC}
      vtExtended:
        AddDouble(VExtended^);
      vtCurrency:
        AddCurr64(VInt64);
      vtObject:
        WriteObject(VObject);
      vtVariant:
        AddVariant(VVariant^, twJsonEscape);
    end;
end;

procedure TTextWriter.AddJsonEscape(Source: TTextWriter);
begin
  if Source.fTotalFileSize = 0 then
    AddJsonEscape(Source.fTempBuf, Source.B - Source.fTempBuf + 1)
  else
    AddJsonEscape(Pointer(Source.Text));
end;

procedure TTextWriter.AddNoJsonEscape(Source: TTextWriter);
begin
  if Source.fTotalFileSize = 0 then
    AddNoJsonEscape(Source.fTempBuf, Source.B - Source.fTempBuf + 1)
  else
    AddNoJsonEscapeUtf8(Source.Text);
end;

procedure TTextWriter.AddJsonString(const Text: RawUtf8);
begin
  Add('"');
  AddJsonEscape(pointer(Text));
  Add('"');
end;

procedure TTextWriter.Add(const V: TVarRec; Escape: TTextWriterKind;
  WriteObjectOptions: TTextWriterWriteObjectOptions);
begin
  with V do
    case VType of
      vtInteger:
        Add(VInteger);
      vtBoolean:
        if VBoolean then // normalize
          Add('1')
        else
          Add('0');
      vtChar:
        Add(@VChar, 1, Escape);
      vtExtended:
        AddDouble(VExtended^);
      vtCurrency:
        AddCurr64(VInt64);
      vtInt64:
        Add(VInt64^);
      {$ifdef FPC}
      vtQWord:
        AddQ(VQWord^);
      {$endif FPC}
      vtVariant:
        AddVariant(VVariant^, Escape);
      vtString:
        if (VString <> nil) and
           (VString^[0] <> #0) then
          Add(@VString^[1], ord(VString^[0]), Escape);
      vtInterface, vtPointer:
        AddPointer(PtrUInt(VPointer));
      vtPChar:
        Add(PUtf8Char(VPChar), Escape);
      vtObject:
        WriteObject(VObject, WriteObjectOptions);
      vtClass:
        AddClassName(VClass);
      vtWideChar:
        AddW(@VWideChar, 1, Escape);
      vtPWideChar:
        AddW(pointer(VPWideChar), StrLenW(VPWideChar), Escape);
      vtAnsiString:
        if VAnsiString <> nil then // expect RawUtf8
          Add(VAnsiString, length(RawUtf8(VAnsiString)), Escape);
      vtWideString:
        if VWideString <> nil then
          AddW(VWideString, length(WideString(VWideString)), Escape);
      {$ifdef HASVARUSTRING}
      vtUnicodeString:
        if VUnicodeString <> nil then // convert to UTF-8
          AddW(VUnicodeString, length(UnicodeString(VUnicodeString)), Escape);
      {$endif HASVARUSTRING}
    end;
end;

procedure TTextWriter.AddJson(const Format: RawUtf8; const Args, Params: array of const);
var
  temp: variant;
begin
  _JsonFmt(Format, Args, Params, JSON_OPTIONS_FAST, temp);
  AddVariant(temp, twJsonEscape);
end;

procedure TTextWriter.AddJsonArraysAsJsonObject(keys, values: PUtf8Char);
var
  k, v: PUtf8Char;
begin
  if (keys = nil) or
     (keys[0] <> '[') or
     (values = nil) or
     (values[0] <> '[') or
     (keys[1] = ']') or
     (values[1] = ']') then
  begin
    AddNull;
    exit;
  end;
  inc(keys); // jump initial [
  inc(values);
  Add('{');
  repeat
    k := GotoEndJsonItem(keys);
    v := GotoEndJsonItem(values);
    if (k = nil) or
       (v = nil) then
      break; // invalid JSON input
    AddNoJsonEscape(keys, k - keys);
    Add(':');
    AddNoJsonEscape(values, v - values);
    AddComma;
    if (k^ <> ',') or
       (v^ <> ',') then
      break; // reached the end of the input JSON arrays
    keys := k + 1;
    values := v + 1;
  until false;
  CancelLastComma;
  Add('}');
end;

procedure TTextWriter.AddJsonEscape(const NameValuePairs: array of const);
var
  a: integer;

  procedure WriteValue;
  begin
    case VarRecAsChar(NameValuePairs[a]) of
      ord('['):
        begin
          Add('[');
          while a < high(NameValuePairs) do
          begin
            inc(a);
            if VarRecAsChar(NameValuePairs[a]) = ord(']') then
              break;
            WriteValue;
          end;
          CancelLastComma;
          Add(']');
        end;
      ord('{'):
        begin
          Add('{');
          while a < high(NameValuePairs) do
          begin
            inc(a);
            if VarRecAsChar(NameValuePairs[a]) = ord('}') then
              break;
            AddJsonEscape(NameValuePairs[a]);
            Add(':');
            inc(a);
            WriteValue;
          end;
          CancelLastComma;
          Add('}');
        end
    else
      AddJsonEscape(NameValuePairs[a]);
    end;
    AddComma;
  end;

begin
  Add('{');
  a := 0;
  while a < high(NameValuePairs) do
  begin
    AddJsonEscape(NameValuePairs[a]);
    inc(a);
    Add(':');
    WriteValue;
    inc(a);
  end;
  CancelLastComma;
  Add('}');
end;

function TTextWriter.AddRecordJson(Value: pointer; RecordInfo: PRttiInfo;
  WriteOptions: TTextWriterWriteObjectOptions): PtrInt;
var
  ctxt: TJsonSaveContext;
begin
  {%H-}ctxt.Init(self, WriteOptions, Rtti.RegisterType(RecordInfo));
  if rcfHasNestedProperties in ctxt.Info.Flags then
    // we know the fields from text definition
    TRttiJsonSave(ctxt.Info.JsonSave)(Value, ctxt)
  else
    // fallback to binary serialization, trailing crc32c and Base64 encoding
    BinarySaveBase64(Value, RecordInfo, rkRecordTypes, {magic=}true);
  result := ctxt.Info.Size;
end;

procedure TTextWriter.AddVoidRecordJson(RecordInfo: PRttiInfo;
  WriteOptions: TTextWriterWriteObjectOptions);
var
  tmp: TSynTempBuffer;
begin
  tmp.InitZero(RecordInfo.RecordSize);
  AddRecordJson(tmp.buf, RecordInfo, WriteOptions);
  tmp.Done;
end;

procedure TTextWriter.AddDynArrayJson(var DynArray: TDynArray;
  WriteOptions: TTextWriterWriteObjectOptions);
var
  ctxt: TJsonSaveContext;
  len, backup: PtrInt;
  hacklen: PDALen;
begin
  len := DynArray.Count;
  if len = 0 then
    Add('[', ']')
  else
  begin
    {%H-}ctxt.Init(self, WriteOptions, DynArray.Info);
    hacklen := PDALen(PAnsiChar(DynArray.Value^) - _DALEN);
    backup := hacklen^;
    hacklen^ := len - _DAOFF; // may use ExternalCount -> ovewrite length(Array)
    _JS_DynArray(DynArray.Value, ctxt);
    hacklen^ := backup; // restore original length/capacity
  end;
end;

procedure TTextWriter.AddDynArrayJson(var DynArray: TDynArrayHashed;
  WriteOptions: TTextWriterWriteObjectOptions);
begin
  // needed if UNDIRECTDYNARRAY is defined (Delphi 2009+)
  AddDynArrayJson(PDynArray(@DynArray)^, WriteOptions);
end;

function TTextWriter.AddDynArrayJson(Value: pointer; Info: TRttiCustom;
  WriteOptions: TTextWriterWriteObjectOptions): PtrInt;
var
  temp: TDynArray;
begin
  if Info.Kind <> rkDynArray then
    raise EDynArray.CreateUtf8('%.AddDynArrayJson: % is %, expected rkDynArray',
      [self, Info.Name, ToText(Info.Kind)^]);
  temp.InitRtti(Info, Value^);
  AddDynArrayJson(temp, WriteOptions);
  result := temp.Info.Cache.ItemSize;
end;


{ ********** Low-Level JSON UnSerialization for all TRttiParserType }

{ TJsonParserContext }

procedure TJsonParserContext.Init(P: PUtf8Char; Rtti: TRttiCustom;
  O: TJsonParserOptions; CV: PDocVariantOptions; ObjectListItemClass: TClass);
begin
  Json := P;
  Valid := true;
  if Rtti <> nil then
    O := O + TRttiJson(Rtti).fIncludeReadOptions;
  Options := O;
  if CV <> nil then
  begin
    DVO := CV^;
    CustomVariant := @DVO;
  end
  else if jpoHandleCustomVariants in O then
  begin
    DVO := JSON_OPTIONS_FAST;
    CustomVariant := @DVO;
  end
  else
    CustomVariant := nil;
  if jpoHandleCustomVariantsWithinString in O then
    include(DVO, dvoJsonObjectParseWithinString);
  Info := Rtti;
  Prop := nil;
  if ObjectListItemClass = nil then
    ObjectListItem := nil
  else
    ObjectListItem := mormot.core.rtti.Rtti.RegisterClass(ObjectListItemClass);
end;

function TJsonParserContext.ParseNext: boolean;
begin
  Value := GetJsonField(Json, Json, @WasString, @EndOfObject, @ValueLen);
  result := Json <> nil;
  Valid := result;
end;

function TJsonParserContext.ParseUtf8: RawUtf8;
begin
  if not ParseNext then
    ValueLen := 0; // return ''
  FastSetString(result, Value, ValueLen)
end;

function TJsonParserContext.ParseString: string;
begin
  if not ParseNext then
    ValueLen := 0; // return ''
  Utf8DecodeToString(Value, ValueLen, result);
end;

function TJsonParserContext.ParseInteger: Int64;
begin
  if ParseNext then
    SetInt64(Value, result{%H-})
  else
    result := 0;
end;

procedure TJsonParserContext.ParseEndOfObject;
begin
  if Valid then
  begin
    if Json^ <> #0 then
      Json := mormot.core.json.ParseEndOfObject(Json, EndOfObject);
    Valid := Json <> nil;
  end;
end;

function TJsonParserContext.ParseNull: boolean;
var
  P: PUtf8Char;
begin
  result := false;
  if Valid then
    if Json <> nil then
    begin
      P := GotoNextNotSpace(Json);
      Json := P;
      if PCardinal(P)^ = NULL_LOW then
      begin
        P := mormot.core.json.ParseEndOfObject(P + 4, EndOfObject);
        if P <> nil then
        begin
          Json := P;
          result := true;
        end
        else
          Valid := false;
      end;
    end
    else
      result := true; // nil -> null
end;

function TJsonParserContext.ParseArray: boolean;
var
  P: PUtf8Char;
begin
  result := false; // no need to parse
  P := GotoNextNotSpace(Json);
  Json := P;
  if P^ = '[' then
  begin
    P := GotoNextNotSpace(P + 1); // ignore trailing [
    if P^ = ']' then
    begin
      // void but valid array
      P := mormot.core.json.ParseEndOfObject(P + 1, EndOfObject);
      Valid := P <> nil;
      Json := P;
    end
    else
    begin
      // we have a non void [...] array -> caller should parse it
      result := true;
      Json := P;
    end;
  end
  else
    Valid := ParseNull; // only not [...] value allowed is null
end;

function TJsonParserContext.ParseNewObject: TObject;
begin
  if ObjectListItem = nil then
  begin
    Info := JsonRetrieveObjectRttiCustom(Json,
      jpoObjectListClassNameGlobalFindClass in Options);
    if (Info <> nil) and
       (Json^ = ',') then
      Json^ := '{' // will now parse other properties as a regular Json object
    else
    begin
      Valid := false;
      result := nil;
      exit;
    end;
  end;
  result := TRttiJson(Info).ParseNewInstance(self);
end;

function TJsonParserContext.ParseObject(const Names: array of RawUtf8;
  Values: PValuePUtf8CharArray; HandleValuesAsObjectOrArray: boolean): boolean;
begin
  Json := JsonDecode(Json, Names, Values, HandleValuesAsObjectOrArray);
  if Json = nil then
    Valid := false
  else
    ParseEndOfObject;
  result := Valid;
end;



procedure _JL_Boolean(Data: PBoolean; var Ctxt: TJsonParserContext);
begin
  if Ctxt.ParseNext then
    Data^ := GetBoolean(Ctxt.Value);
end;

procedure _JL_Byte(Data: PByte; var Ctxt: TJsonParserContext);
begin
  if Ctxt.ParseNext then
    Data^ := GetCardinal(Ctxt.Value);
end;

procedure _JL_Cardinal(Data: PCardinal; var Ctxt: TJsonParserContext);
begin
  if Ctxt.ParseNext then
    Data^ := GetCardinal(Ctxt.Value);
end;

procedure _JL_Integer(Data: PInteger; var Ctxt: TJsonParserContext);
begin
  if Ctxt.ParseNext then
    Data^ := GetInteger(Ctxt.Value);
end;

procedure _JL_Currency(Data: PInt64; var Ctxt: TJsonParserContext);
begin
  if Ctxt.ParseNext then
    Data^ := StrToCurr64(Ctxt.Value);
end;

procedure _JL_Double(Data: PDouble; var Ctxt: TJsonParserContext);
var
  err: integer;
begin
  if Ctxt.ParseNext then
  begin
    unaligned(Data^) := GetExtended(Ctxt.Value, err);
    Ctxt.Valid := err = 0;
  end;
end;

procedure _JL_Extended(Data: PSynExtended; var Ctxt: TJsonParserContext);
var
  err: integer;
begin
  if Ctxt.ParseNext then
  begin
    Data^ := GetExtended(Ctxt.Value, err);
    Ctxt.Valid := err = 0;
  end;
end;

procedure _JL_Int64(Data: PInt64; var Ctxt: TJsonParserContext);
begin
  if Ctxt.ParseNext then
    if Ctxt.WasString and
       (Ctxt.ValueLen = SizeOf(Data^) * 2) then
      Ctxt.Valid := (jpoAllowInt64Hex in Ctxt.Options) and
        HexDisplayToBin(PAnsiChar(Ctxt.Value), pointer(Data), SizeOf(Data^))
    else
      SetInt64(Ctxt.Value, Data^);
end;

procedure _JL_QWord(Data: PQWord; var Ctxt: TJsonParserContext);
begin
  if Ctxt.ParseNext then
    if Ctxt.WasString and
       (Ctxt.ValueLen = SizeOf(Data^) * 2) then
      Ctxt.Valid := (jpoAllowInt64Hex in Ctxt.Options) and
        HexDisplayToBin(PAnsiChar(Ctxt.Value), pointer(Data), SizeOf(Data^))
    else
      SetQWord(Ctxt.Value, Data^);
end;

procedure _JL_RawByteString(Data: PRawByteString; var Ctxt: TJsonParserContext);
begin
  if Ctxt.ParseNext then
    if Ctxt.Value = nil then // null
      Data^ := ''
    else
      Ctxt.Valid := Base64MagicCheckAndDecode(Ctxt.Value, Ctxt.ValueLen, Data^);
end;

procedure _JL_RawJson(Data: PRawJson; var Ctxt: TJsonParserContext);
begin
  GetJsonItemAsRawJson(Ctxt.Json, Data^, @Ctxt.EndOfObject);
  Ctxt.Valid := Ctxt.Json <> nil;
end;

procedure _JL_RawUtf8(Data: PRawByteString; var Ctxt: TJsonParserContext);
begin
  if Ctxt.ParseNext then
    // will handle RawUtf8 but also AnsiString, WinAnsiString and RawUnicode
    if Ctxt.Info.Cache.CodePage = CP_UTF8 then
      FastSetString(RawUtf8(Data^), Ctxt.Value, Ctxt.ValueLen)
    else if Ctxt.Info.Cache.CodePage >= CP_RAWBLOB then
      Ctxt.Valid := false // paranoid check (RawByteString should handle it)
    else
      Ctxt.Info.Cache.Engine.Utf8BufferToAnsi(Ctxt.Value, Ctxt.ValueLen, Data^);
end;

procedure _JL_Single(Data: PSingle; var Ctxt: TJsonParserContext);
begin
  if Ctxt.ParseNext then
    Data^ := GetExtended(Ctxt.Value);
end;

procedure _JL_String(Data: PString; var Ctxt: TJsonParserContext);
begin
  if Ctxt.ParseNext then
    Utf8DecodeToString(Ctxt.Value, Ctxt.ValueLen, Data^);
end;

procedure _JL_SynUnicode(Data: PSynUnicode; var Ctxt: TJsonParserContext);
begin
  if Ctxt.ParseNext then
    Utf8ToSynUnicode(Ctxt.Value, Ctxt.ValueLen, Data^);
end;

procedure _JL_DateTime(Data: PDateTime; var Ctxt: TJsonParserContext);
begin
  if Ctxt.ParseNext then
    if Ctxt.WasString then
      Iso8601ToDateTimePUtf8CharVar(Ctxt.Value, Ctxt.ValueLen, Data^)
    else
      Data^ := GetExtended(Ctxt.Value); // was propbably stored as double
end;

procedure _JL_GUID(Data: PByteArray; var Ctxt: TJsonParserContext);
begin
  if Ctxt.ParseNext then
    Ctxt.Valid := TextToGuid(Ctxt.Value, Data) <> nil;
end;

procedure _JL_Hash(Data: PByte; var Ctxt: TJsonParserContext);
begin
  if Ctxt.ParseNext then
    Ctxt.Valid := (Ctxt.ValueLen = Ctxt.Info.Size * 2) and
      HexDisplayToBin(PAnsiChar(Ctxt.Value), Data, Ctxt.Info.Size);
end;

procedure _JL_Binary(Data: PByte; var Ctxt: TJsonParserContext);
var
  v: QWord;
begin
  if Ctxt.ParseNext then
    if Ctxt.WasString then
    begin
      FillZeroSmall(Data, Ctxt.Info.Size);
      if Ctxt.ValueLen > 0 then // "" -> is valid 0
        Ctxt.Valid := (Ctxt.ValueLen = Ctxt.Info.BinarySize * 2) and
          HexDisplayToBin(PAnsiChar(Ctxt.Value), Data, Ctxt.Info.BinarySize);
    end
    else
    begin
      SetQWord(Ctxt.Value, v{%H-});
      MoveSmall(@v, Data, Ctxt.Info.Size);
    end;
end;

procedure _JL_TimeLog(Data: PQWord; var Ctxt: TJsonParserContext);
begin
  if Ctxt.ParseNext then
    if Ctxt.WasString then
      Data^ := Iso8601ToTimeLogPUtf8Char(Ctxt.Value, Ctxt.ValueLen)
    else
      SetQWord(Ctxt.Value, Data^);
end;

procedure _JL_UnicodeString(Data: pointer; var Ctxt: TJsonParserContext);
begin
  Ctxt.ParseNext;
  {$ifdef HASVARUSTRING}
  if Ctxt.Valid then
    Utf8DecodeToUnicodeString(Ctxt.Value, Ctxt.ValueLen, PUnicodeString(Data)^);
  {$endif HASVARUSTRING}
end;

procedure _JL_UnixTime(Data: PQWord; var Ctxt: TJsonParserContext);
begin
  if Ctxt.ParseNext then
    if Ctxt.WasString then
      Data^ := TimeLogToUnixTime(Iso8601ToTimeLogPUtf8Char(
        Ctxt.Value, Ctxt.ValueLen))
    else
      SetQWord(Ctxt.Value, Data^);
end;

procedure _JL_UnixMSTime(Data: PQWord; var Ctxt: TJsonParserContext);
var
  dt: TDateTime; // for ms resolution
begin
  if Ctxt.ParseNext then
    if Ctxt.WasString then
    begin
      Iso8601ToDateTimePUtf8CharVar(Ctxt.Value, Ctxt.ValueLen, dt);
      Data^ := DateTimeToUnixMSTime(dt);
    end
    else
      SetQWord(Ctxt.Value, Data^);
end;

procedure _JL_Variant(Data: PVariant; var Ctxt: TJsonParserContext);
begin
  Ctxt.Json := VariantLoadJson(Data^, Ctxt.Json, @Ctxt.EndOfObject,
    Ctxt.CustomVariant, jpoAllowDouble in Ctxt.Options);
  Ctxt.Valid := Ctxt.Json <> nil;
end;

procedure _JL_WideString(Data: PWideString; var Ctxt: TJsonParserContext);
begin
  if Ctxt.ParseNext then
    Utf8ToWideString(Ctxt.Value, Ctxt.ValueLen, Data^);
end;

procedure _JL_WinAnsi(Data: PRawByteString; var Ctxt: TJsonParserContext);
begin
  if Ctxt.ParseNext then
    WinAnsiConvert.Utf8BufferToAnsi(Ctxt.Value, Ctxt.ValueLen, Data^);
end;

procedure _JL_Word(Data: PWord; var Ctxt: TJsonParserContext);
begin
  if Ctxt.ParseNext then
    Data^ := GetCardinal(Ctxt.Value);
end;

procedure _JL_Enumeration(Data: pointer; var Ctxt: TJsonParserContext);
var
  v: PtrInt;
  err: integer;
begin
  if Ctxt.ParseNext then
  begin
    if Ctxt.WasString then
      v := Ctxt.Info.Cache.EnumInfo.GetEnumNameValue(Ctxt.Value, Ctxt.ValueLen)
    else
    begin
      v := GetInteger(Ctxt.Value, err);
      if (err <> 0) or
         (PtrUInt(v) > Ctxt.Info.Cache.EnumMax) then
        v := -1;
    end;
    if v < 0 then
      if jpoIgnoreUnknownEnum in Ctxt.Options then
        v := 0
      else
        Ctxt.Valid := false;
    MoveSmall(@v, Data, Ctxt.Info.Size);
  end;
end;

procedure _JL_Set(Data: pointer; var Ctxt: TJsonParserContext);
var
  v: QWord;
begin
  v := GetSetNameValue(Ctxt.Info.Cache.EnumList,
    Ctxt.Info.Cache.EnumMax, Ctxt.Json, Ctxt.EndOfObject);
  Ctxt.Valid := Ctxt.Json <> nil;
  MoveSmall(@v, Data, Ctxt.Info.Size);
end;

function JsonLoadProp(Data: PAnsiChar; const Prop: TRttiCustomProp;
  var Ctxt: TJsonParserContext): boolean; {$ifdef HASINLINE} inline; {$endif}
var
  load: TRttiJsonLoad;
begin
  Ctxt.Info := Prop.Value; // caller will restore it afterwards
  Ctxt.Prop := @Prop;
  load := Ctxt.Info.JsonLoad;
  if not Assigned(load) then
    Ctxt.Valid := false
  else if Prop.OffsetSet >= 0 then
    if (rcfHookReadProperty in Ctxt.Info.Flags) and
       TCCHook(Data).RttiBeforeReadPropertyValue(@Ctxt, @Prop) then
      // custom parsing method (e.g. TOrm nested TOrm properties)
    else
      // default fast parsing into the property/field memory
      load(Data + Prop.OffsetSet, Ctxt)
  else
    // we need to call a setter
    Ctxt.ParsePropComplex(Data);
  Ctxt.Prop := nil;
  result := Ctxt.Valid;
end;

procedure _JL_RttiCustomProps(Data: PAnsiChar; var Ctxt: TJsonParserContext);
var
  root: TRttiJson;
  p: integer;
  prop: PRttiCustomProp;
  propname: PUtf8Char;
  propnamelen: integer;
label
  nxt, any;
begin
  // regular JSON unserialization using nested fields/properties
  Ctxt.Json := GotoNextNotSpace(Ctxt.Json);
  if Ctxt.Json^ <> '{' then
  begin
    Ctxt.Valid := false;
    exit;
  end;
  Ctxt.Json := GotoNextNotSpace(Ctxt.Json + 1);
  if Ctxt.Json^ <> '}' then
  begin
    root := pointer(Ctxt.Info); // Ctxt.Info overriden in JsonLoadProp()
    prop := pointer(root.Props.List);
    for p := 1 to root.Props.Count do
    begin
nxt:  propname := GetJsonPropName(Ctxt.Json, @propnamelen);
      Ctxt.Valid := (Ctxt.Json <> nil) and
                    (propname <> nil);
      if not Ctxt.Valid then
        break;
      // O(1) optimistic process of the property name, following RTTI order
      if (prop^.Name <> '') and
         IdemPropNameU(prop^.Name, propname, propnamelen) then
        if JsonLoadProp(Data, prop^, Ctxt) then
          if Ctxt.EndOfObject = '}' then
            break
          else
            inc(prop)
        else
          break
      else if (Ctxt.Info.Kind = rkClass) and
              IdemPropName('ClassName', propname, propnamelen) then
      begin
        // woStoreClassName was used -> just ignore the class name
        Ctxt.Json := GotoNextJsonItem(Ctxt.Json, 1, @Ctxt.EndOfObject);
        Ctxt.Valid := Ctxt.Json <> nil;
        if Ctxt.Valid then
          goto nxt;
        break;
      end
      else
      begin
        // we didn't find the property in its natural place -> full lookup
        repeat
          prop := root.Props.Find(propname, propnamelen);
          if prop = nil then
            // unexpected "prop": value
            if (rcfReadIgnoreUnknownFields in root.Flags) or
               (jpoIgnoreUnknownProperty in Ctxt.Options) then
            begin
              Ctxt.Json := GotoNextJsonItem(Ctxt.Json, 1, @Ctxt.EndOfObject);
              Ctxt.Valid := Ctxt.Json <> nil;
            end
            else
              Ctxt.Valid := false
          else
            Ctxt.Valid := JsonLoadProp(Data, prop^, Ctxt);
          if (not Ctxt.Valid) or
             (Ctxt.EndOfObject = '}') then
             break;
any:      propname := GetJsonPropName(Ctxt.Json, @propnamelen);
          Ctxt.Valid := (Ctxt.Json <> nil) and
                        (propname <> nil);
        until not Ctxt.Valid;
        break;
      end;
    end;
    if Ctxt.Valid and
       (Ctxt.EndOfObject = ',') and
       ((rcfReadIgnoreUnknownFields in root.Flags) or
        (jpoIgnoreUnknownProperty in Ctxt.Options)) then
      goto any;
    Ctxt.ParseEndOfObject; // mimics GetJsonField() - set Ctxt.EndOfObject
    Ctxt.Info := root; // restore
  end
  else
  begin
    inc(Ctxt.Json);
    Ctxt.ParseEndOfObject;
  end
end;

procedure _JL_RttiCustom(Data: PAnsiChar; var Ctxt: TJsonParserContext);
begin
  if Ctxt.Json <> nil then
    Ctxt.Json := GotoNextNotSpace(Ctxt.Json);
  if TRttiJson(Ctxt.Info).fJsonReader.Code <> nil then
  begin
    // TRttiJson.RegisterCustomSerializer() custom callbacks
    if Ctxt.Info.Kind = rkClass then
      Data := PPointer(Data)^; // as expected by the callback
    TOnRttiJsonRead(TRttiJson(Ctxt.Info).fJsonReader)(Ctxt, Data)
  end
  else
  begin
    // always finalize and reset the existing values (in case of missing props)
    if Ctxt.Info.Kind = rkClass then
    begin
      if Ctxt.ParseNull then
      begin
        if not (jpoNullDontReleaseObjectInstance in Ctxt.Options) then
          FreeAndNil(PObject(Data)^);
        exit;
      end;
      if PPointer(Data)^ = nil then
        // e.g. from _JL_DynArray for T*ObjArray
        PPointer(Data)^ := TRttiJson(Ctxt.Info).fClassNewInstance(Ctxt.Info)
      else if jpoClearValues in Ctxt.Options then
        Ctxt.Info.Props.FinalizeAndClearPublishedProperties(PPointer(Data)^);
      // class instances are accessed by reference, records are stored by value
      Data := PPointer(Data)^;
      if (rcfHookRead in Ctxt.Info.Flags) and
         (TCCHook(Data).RttiBeforeReadObject(@Ctxt)) then
        exit;
    end
    else
    begin
      if jpoClearValues in Ctxt.Options then
        Ctxt.Info.ValueFinalizeAndClear(Data);
      if Ctxt.ParseNull then
        exit;
    end;
    // regular JSON unserialization using nested fields/properties
    _JL_RttiCustomProps(Data, Ctxt);
    if rcfHookRead in Ctxt.Info.Flags then
      TCCHook(Data).RttiAfterReadObject;
  end;
end;

procedure _JL_Array(Data: PAnsiChar; var Ctxt: TJsonParserContext);
var
  n: integer;
  arrinfo: TRttiCustom;
begin
  if not Ctxt.ParseArray then
    // detect void (i.e. []) or invalid array
    exit;
  if PCardinal(Ctxt.Json)^ = JSON_BASE64_MAGIC_QUOTE_C then
    // raw RTTI binary layout with a single Base-64 encoded item
    Ctxt.Valid := Ctxt.ParseNext and
              (Ctxt.EndOfObject = ']') and
              (Ctxt.Value <> nil) and
              (PCardinal(Ctxt.Value)^ and $ffffff = JSON_BASE64_MAGIC_C) and
              BinaryLoadBase64(pointer(Ctxt.Value + 3), Ctxt.ValueLen - 3,
                Data, Ctxt.Info.Info, {uri=}false, [rkArray], {withcrc=}false)
  else
  begin
    // efficient load of all JSON items
    arrinfo := Ctxt.Info;
    Ctxt.Info := arrinfo.ArrayRtti; // nested context = item
    n := arrInfo.Cache.ItemCount;
    repeat
      TRttiJsonLoad(Ctxt.Info.JsonLoad)(Data, Ctxt);
      dec(n);
      if Ctxt.Valid then
        if (n > 0) and
           (Ctxt.EndOfObject = ',') then
        begin
          // continue with the next item
          inc(Data, arrinfo.Cache.ItemSize);
          continue;
        end
        else if (n = 0) and
                (Ctxt.EndOfObject = ']') then
          // reached end of arrray
          break;
      Ctxt.Valid := false; // unexpected end
      exit;
    until false;
    Ctxt.Info := arrinfo;
  end;
  Ctxt.ParseEndOfObject; // mimics GetJsonField() / Ctxt.ParseNext
end;

procedure _JL_DynArray_Custom(Data: PAnsiChar; var Ctxt: TJsonParserContext);
begin
  // TRttiJson.RegisterCustomSerializer() custom callback for each item
  TOnRttiJsonRead(TRttiJson(Ctxt.Info).fJsonReader)(Ctxt, Data);
end;

procedure _JL_DynArray(Data: PAnsiChar; var Ctxt: TJsonParserContext);
var
  load: TRttiJsonLoad;
  n, cap: PtrInt;
  arr: PPointer;
  arrinfo: TRttiCustom;
begin
  arr := pointer(Data);
  if arr^ <> nil then
    Ctxt.Info.ValueFinalize(arr); // reset whole array variable
  if not Ctxt.ParseArray then
    // detect void (i.e. []) or invalid array
    exit;
  if PCardinal(Ctxt.Json)^ = JSON_BASE64_MAGIC_QUOTE_C then
    // raw RTTI binary layout with a single Base-64 encoded item
    Ctxt.Valid := Ctxt.ParseNext and
              (Ctxt.EndOfObject = ']') and
              (Ctxt.Value <> nil) and
              (PCardinal(Ctxt.Value)^ and $ffffff = JSON_BASE64_MAGIC_C) and
              BinaryLoadBase64(pointer(Ctxt.Value + 3), Ctxt.ValueLen - 3,
                Data, Ctxt.Info.Info, {uri=}false, [rkDynArray], {withcrc=}false)
  else
  begin
    // efficient load of all JSON items
    arrinfo := Ctxt.Info;
    if TRttiJson(arrinfo).fJsonReader.Code <> nil then
      // TRttiJson.RegisterCustomSerializer() custom callbacks
      load := @_JL_DynArray_Custom
    else
    begin
      Ctxt.Info := arrinfo.ArrayRtti;
      if Ctxt.Info = nil then
        load := nil
      else
      begin
        load := Ctxt.Info.JsonLoad;
        if (@load = @_JL_RttiCustom) and
           (TRttiJson(Ctxt.Info).fJsonReader.Code = nil) and
           (Ctxt.Info.Kind <> rkClass) and
           (not (jpoClearValues in Ctxt.Options)) then
          load := @_JL_RttiCustomProps; // somewhat faster direct record load
      end;
    end;
    // initial guess of the JSON array count - will browse up to 64KB of input
    cap := abs(JsonArrayCount(Ctxt.Json, Ctxt.Json + JSON_ARRAY_PRELOAD));
    if (cap = 0) or
       not Assigned(load) then
    begin
      Ctxt.Valid := false;
      exit;
    end;
    Data := DynArrayNew(arr, cap, arrinfo.Cache.ItemSize); // alloc zeroed mem
    // main JSON unserialization loop
    n := 0;
    repeat
      if n = cap then
      begin
        // grow if our initial guess was aborted due to huge input
        cap := NextGrow(cap);
        Data := DynArrayGrow(arr, cap, arrinfo.Cache.ItemSize) +
                  (n * arrinfo.Cache.ItemSize);
      end;
      // unserialize one item
      load(Data, Ctxt); // will call _JL_RttiCustom() for T*ObjArray
      inc(n);
      if Ctxt.Valid then
        if Ctxt.EndOfObject = ',' then
        begin
          // continue with the next item
          inc(Data, arrinfo.Cache.ItemSize);
          continue;
        end
        else if Ctxt.EndOfObject = ']' then
          // reached end of arrray
          break;
      Ctxt.Valid := false; // unexpected end
      arrinfo.ValueFinalize(arr); // whole array clear on error
      exit;
    until false;
    if n <> cap then
      // don't size down the grown memory buffer, just fake its length
      PDALen(PAnsiChar(arr^) - _DALEN)^ := n - _DAOFF;
    Ctxt.Info := arrinfo;
  end;
  Ctxt.ParseEndOfObject; // mimics GetJsonField() / Ctxt.ParseNext
end;

procedure _JL_Interface(Data: PInterface; var Ctxt: TJsonParserContext);
begin
  Ctxt.Valid := Ctxt.ParseNull;
  Data^ := nil;
end;

// defined here to have _JL_RawJson and _JL_Variant known
procedure TJsonParserContext.ParsePropComplex(Data: pointer);
var
  v: TRttiVarData;
  tmp: TObject;
begin
  if Info.Kind = rkClass then
  begin
    // special case of a setter method for a class property: use a temp instance
    if jpoSetterNoCreate in Options then
      Valid := false
    else
    begin
      tmp := TRttiJson(Info).fClassNewInstance(Info);
      try
        v.Prop := Prop; // JsonLoad() would reset Prop := nil
        TRttiJsonLoad(Info.JsonLoad)(@tmp, self); // JsonToObject(tmp)
        if not Valid then
          FreeAndNil(tmp)
        else
        begin
          v.Prop.Prop.SetOrdProp(Data, PtrInt(tmp));
          if jpoSetterExpectsToFreeTempInstance in Options then
            FreeAndNil(tmp);
        end;
      except
        on Exception do
          tmp.Free;
      end;
    end;
    exit;
  end
  else if Info.Parser = ptRawJson then
  begin
    // TRttiProp.SetValue() assume RawUtF8 -> dedicated RawJson code
    v.VType := varString;
    v.Data.VAny := nil;
    _JL_RawJson(@v.Data.VAny, self);
    if Valid then
      Prop^.Prop.SetLongStrProp(Data, RawJson(v.Data.VAny));
  end
  else
  begin
    // call the getter via TRttiProp.SetValue() of a transient TRttiVarData
    v.VType := 0;
    _JL_Variant(@v, self); // VariantLoadJson() over Ctxt
    if Valid then
      Valid := Prop^.Prop.SetValue(Data, variant(v));
  end;
  VarClearProc(v.Data);
end;

procedure _JL_TObjectList(Data: PObjectList; var Ctxt: TJsonParserContext);
var
  root: TRttiCustom;
  item: TObject;
begin
  if Data^ = nil then
  begin
    Ctxt.Valid := Ctxt.ParseNull;
    exit;
  end;
  Data^.Clear;
  if Ctxt.ParseNull or
     not Ctxt.ParseArray then
    exit;
  root := Ctxt.Info;
  Ctxt.Info := Ctxt.ObjectListItem;
  repeat
    item := Ctxt.ParseNewObject;
    if item = nil then
      break;
    Data^.Add(item);
  until Ctxt.EndOfObject = ']';
  Ctxt.Info := root;
  Ctxt.ParseEndOfObject;
end;

procedure _JL_TCollection(Data: PCollection; var Ctxt: TJsonParserContext);
var
  root: TRttiJson;
  load: TRttiJsonLoad;
  item: TCollectionItem;
begin
  if Data^ = nil then
  begin
    Ctxt.Valid := Ctxt.ParseNull;
    exit;
  end;
  Data^.BeginUpdate;
  try
    Data^.Clear;
    if Ctxt.ParseNull or
       not Ctxt.ParseArray then
      exit;
    root := TRttiJson(Ctxt.Info);
    load := nil;
    repeat
      item := Data^.Add;
      if not Assigned(load) then
      begin
        if root.fCollectionItemRtti = nil then
        begin
          // RegisterCollection() was not called -> compute after Data^.Add
          root.fCollectionItem := PPointer(item)^;
          root.fCollectionItemRtti := Rtti.RegisterClass(PClass(item)^);
        end;
        Ctxt.Info := root.fCollectionItemRtti;
        load := Ctxt.Info.JsonLoad;
      end;
      load(@item, Ctxt);
    until (not Ctxt.Valid) or
          (Ctxt.EndOfObject = ']');
    Ctxt.Info := root;
    Ctxt.ParseEndOfObject;
  finally
    Data^.EndUpdate;
  end;
end;

procedure _JL_TSynObjectList(Data: PSynObjectList; var Ctxt: TJsonParserContext);
var
  root: TRttiCustom;
  item: TObject;
begin
  if Data^ = nil then
  begin
    Ctxt.Valid := Ctxt.ParseNull;
    exit;
  end;
  Data^.Clear;
  if Ctxt.ParseNull or
     not Ctxt.ParseArray then
    exit;
  root := Ctxt.Info;
  Ctxt.Info := Ctxt.ObjectListItem;
  repeat
    item := Ctxt.ParseNewObject;
    if item = nil then
      break;
    Data^.Add(item);
  until Ctxt.EndOfObject = ']';
  Ctxt.Info := root;
  Ctxt.ParseEndOfObject;
end;

procedure _JL_TStrings(Data: PStrings; var Ctxt: TJsonParserContext);
var
  item: string;
begin
  if Data^ = nil then
  begin
    Ctxt.Valid := Ctxt.ParseNull;
    exit;
  end;
  Data^.BeginUpdate;
  try
    Data^.Clear;
    if Ctxt.ParseNull or
       not Ctxt.ParseArray then
      exit;
    repeat
      if Ctxt.ParseNext then
      begin
        Utf8DecodeToString(Ctxt.Value, Ctxt.ValueLen, item);
        Data^.Add(item);
      end;
    until (not Ctxt.Valid) or
          (Ctxt.EndOfObject = ']');
  finally
    Data^.EndUpdate;
  end;
  Ctxt.ParseEndOfObject;
end;

procedure _JL_TRawUtf8List(Data: PRawUtf8List; var Ctxt: TJsonParserContext);
var
  item: RawUtf8;
begin
  if Data^ = nil then
  begin
    Ctxt.Valid := Ctxt.ParseNull;
    exit;
  end;
  Data^.BeginUpdate;
  try
    Data^.Clear;
    if Ctxt.ParseNull or
       not Ctxt.ParseArray then
      exit;
    repeat
      if Ctxt.ParseNext then
      begin
        FastSetString(item, Ctxt.Value, Ctxt.ValueLen);
        Data^.AddObject(item, nil);
      end;
    until (not Ctxt.Valid) or
          (Ctxt.EndOfObject = ']');
  finally
    Data^.EndUpdate;
  end;
  Ctxt.ParseEndOfObject;
end;

var
  /// use pointer to allow any kind of Data^ type in above functions
  // - typecast to TRttiJsonSave for proper function call
  // - rkRecord and rkClass are set in TRttiJson.SetParserType
  PT_JSONLOAD: array[TRttiParserType] of pointer = (
    nil, @_JL_Array, @_JL_Boolean, @_JL_Byte, @_JL_Cardinal, @_JL_Currency,
    @_JL_Double, @_JL_Extended, @_JL_Int64, @_JL_Integer, @_JL_QWord,
    @_JL_RawByteString, @_JL_RawJson, @_JL_RawUtf8, nil,
    @_JL_Single, @_JL_String, @_JL_SynUnicode, @_JL_DateTime, @_JL_DateTime,
    @_JL_GUID, @_JL_Hash, @_JL_Hash, @_JL_Hash, @_JL_Int64, @_JL_TimeLog,
    @_JL_UnicodeString, @_JL_UnixTime, @_JL_UnixMSTime, @_JL_Variant,
    @_JL_WideString, @_JL_WinAnsi, @_JL_Word, @_JL_Enumeration, @_JL_Set,
    nil, @_JL_DynArray, @_JL_Interface, nil);


{ ************ JSON-aware TSynNameValue TSynPersistentStoreJson }

{ TSynNameValue }

procedure TSynNameValue.Add(const aName, aValue: RawUtf8; aTag: PtrInt);
var
  added: boolean;
  i: integer;
begin
  i := DynArray.FindHashedForAdding(aName, added);
  with List[i] do
  begin
    if added then
      Name := aName;
    Value := aValue;
    Tag := aTag;
  end;
  if Assigned(fOnAdd) then
    fOnAdd(List[i], i);
end;

procedure TSynNameValue.InitFromIniSection(Section: PUtf8Char;
  const OnTheFlyConvert: TOnSynNameValueConvertRawUtf8;
  const OnAdd: TOnSynNameValueNotify);
var
  s: RawUtf8;
  i: integer;
begin
  Init(false);
  fOnAdd := OnAdd;
  while (Section <> nil) and
        (Section^ <> '[') do
  begin
    s := GetNextLine(Section, Section);
    i := PosExChar('=', s);
    if (i > 1) and
       not (s[1] in [';', '[']) then
      if Assigned(OnTheFlyConvert) then
        Add(copy(s, 1, i - 1), OnTheFlyConvert(copy(s, i + 1, 1000)))
      else
        Add(copy(s, 1, i - 1), copy(s, i + 1, 1000));
  end;
end;

procedure TSynNameValue.InitFromCsv(Csv: PUtf8Char; NameValueSep, ItemSep: AnsiChar);
var
  n, v: RawUtf8;
begin
  Init(false);
  while Csv <> nil do
  begin
    GetNextItem(Csv, NameValueSep, n);
    if ItemSep = #10 then
      GetNextItemTrimedCRLF(Csv, v)
    else
      GetNextItem(Csv, ItemSep, v);
    if n = '' then
      break;
    Add(n, v);
  end;
end;

procedure TSynNameValue.InitFromNamesValues(const Names, Values: array of RawUtf8);
var
  i: integer;
begin
  Init(false);
  if high(Names) <> high(Values) then
    exit;
  DynArray.Capacity := length(Names);
  for i := 0 to high(Names) do
    Add(Names[i], Values[i]);
end;

function TSynNameValue.InitFromJson(Json: PUtf8Char; aCaseSensitive: boolean): boolean;
var
  N, V: PUtf8Char;
  nam, val: RawUtf8;
  Nlen, Vlen, c: integer;
  EndOfObject: AnsiChar;
begin
  result := false;
  Init(aCaseSensitive);
  if Json = nil then
    exit;
  while (Json^ <= ' ') and
        (Json^ <> #0) do
    inc(Json);
  if Json^ <> '{' then
    exit;
  repeat
    inc(Json)
  until (Json^ = #0) or
        (Json^ > ' ');
  c := JsonObjectPropCount(Json);
  if c <= 0 then
    exit;
  DynArray.Capacity := c;
  repeat
    N := GetJsonPropName(Json, @Nlen);
    if N = nil then
      exit;
    V := GetJsonFieldOrObjectOrArray(Json, nil, @EndOfObject, true, true, @Vlen);
    if Json = nil then
      exit;
    FastSetString(nam, N, Nlen);
    FastSetString(val, V, Vlen);
    Add(nam, val);
  until EndOfObject = '}';
  result := true;
end;

procedure TSynNameValue.Init(aCaseSensitive: boolean);
begin
  // release dynamic arrays memory before FillcharFast()
  List := nil;
  DynArray.Hasher.Clear;
  // initialize hashed storage
  FillCharFast(self, SizeOf(self), 0);
  DynArray.InitSpecific(TypeInfo(TSynNameValueItemDynArray), List,
    ptRawUtf8, @Count, not aCaseSensitive);
end;

function TSynNameValue.Find(const aName: RawUtf8): integer;
begin
  result := DynArray.FindHashed(aName);
end;

function TSynNameValue.FindStart(const aUpperName: RawUtf8): PtrInt;
begin
  for result := 0 to Count - 1 do
    if IdemPChar(pointer(List[result].Name), pointer(aUpperName)) then
      exit;
  result := -1;
end;

function TSynNameValue.FindByValue(const aValue: RawUtf8): PtrInt;
begin
  for result := 0 to Count - 1 do
    if List[result].Value = aValue then
      exit;
  result := -1;
end;

function TSynNameValue.Delete(const aName: RawUtf8): boolean;
begin
  result := DynArray.FindHashedAndDelete(aName) >= 0;
end;

function TSynNameValue.DeleteByValue(const aValue: RawUtf8; Limit: integer): integer;
var
  ndx: PtrInt;
begin
  result := 0;
  if Limit < 1 then
    exit;
  for ndx := Count - 1 downto 0 do
    if List[ndx].Value = aValue then
    begin
      DynArray.Delete(ndx);
      inc(result);
      if result >= Limit then
        break;
    end;
  if result > 0 then
    DynArray.ReHash;
end;

function TSynNameValue.Value(const aName: RawUtf8; const aDefaultValue: RawUtf8): RawUtf8;
var
  i: integer;
begin
  if @self = nil then
    i := -1
  else
    i := DynArray.FindHashed(aName);
  if i < 0 then
    result := aDefaultValue
  else
    result := List[i].Value;
end;

function TSynNameValue.ValueInt(const aName: RawUtf8; const aDefaultValue: Int64): Int64;
var
  i, err: integer;
begin
  i := DynArray.FindHashed(aName);
  if i < 0 then
    result := aDefaultValue
  else
  begin
    result := GetInt64(pointer(List[i].Value), err);
    if err <> 0 then
      result := aDefaultValue;
  end;
end;

function TSynNameValue.ValueBool(const aName: RawUtf8): boolean;
begin
  result := Value(aName) = '1';
end;

function TSynNameValue.ValueEnum(const aName: RawUtf8; aEnumTypeInfo: PRttiInfo;
  out aEnum; aEnumDefault: PtrUInt): boolean;
var
  rtti: PRttiEnumType;
  v: RawUtf8;
  err: integer;
  i: PtrInt;
begin
  result := false;
  rtti := aEnumTypeInfo.EnumBaseType;
  if rtti = nil then
    exit;
  ToRttiOrd(rtti.RttiOrd, @aEnum, aEnumDefault); // always set the default value
  v := TrimU(Value(aName, ''));
  if v = '' then
    exit;
  i := GetInteger(pointer(v), err);
  if (err <> 0) or
     (PtrUInt(i) > PtrUInt(rtti.MaxValue)) then
    i := rtti.GetEnumNameValue(pointer(v), length(v), {alsotrimleft=}true);
  if i >= 0 then
  begin
    ToRttiOrd(rtti.RttiOrd, @aEnum, i); // we found a proper value
    result := true;
  end;
end;

function TSynNameValue.Initialized: boolean;
begin
  result := DynArray.Value = @List;
end;

function TSynNameValue.GetBlobData: RawByteString;
begin
  result := DynArray.SaveTo;
end;

procedure TSynNameValue.SetBlobDataPtr(aValue: pointer);
begin
  DynArray.LoadFrom(aValue);
  DynArray.ReHash;
end;

procedure TSynNameValue.SetBlobData(const aValue: RawByteString);
begin
  DynArray.LoadFromBinary(aValue);
  DynArray.ReHash;
end;

function TSynNameValue.GetStr(const aName: RawUtf8): RawUtf8;
begin
  result := Value(aName, '');
end;

function TSynNameValue.GetInt(const aName: RawUtf8): Int64;
begin
  result := ValueInt(aName, 0);
end;

function TSynNameValue.GetBool(const aName: RawUtf8): boolean;
begin
  result := Value(aName) = '1';
end;

function TSynNameValue.AsCsv(const KeySeparator, ValueSeparator, IgnoreKey: RawUtf8): RawUtf8;
var
  i: PtrInt;
  temp: TTextWriterStackBuffer;
begin
  with TBaseWriter.CreateOwnedStream(temp) do
  try
    for i := 0 to Count - 1 do
      if (IgnoreKey = '') or
         (List[i].Name <> IgnoreKey) then
      begin
        AddNoJsonEscapeUtf8(List[i].Name);
        AddNoJsonEscapeUtf8(KeySeparator);
        AddNoJsonEscapeUtf8(List[i].Value);
        AddNoJsonEscapeUtf8(ValueSeparator);
      end;
    SetText(result);
  finally
    Free;
  end;
end;

function TSynNameValue.AsJson: RawUtf8;
var
  i: PtrInt;
  temp: TTextWriterStackBuffer;
begin
  with TTextWriter.CreateOwnedStream(temp) do
  try
    Add('{');
    for i := 0 to Count - 1 do
      with List[i] do
      begin
        AddProp(pointer(Name), length(Name));
        Add('"');
        AddJsonEscape(pointer(Value));
        Add('"', ',');
      end;
    CancelLastComma;
    Add('}');
    SetText(result);
  finally
    Free;
  end;
end;

procedure TSynNameValue.AsNameValues(out Names, Values: TRawUtf8DynArray);
var
  i: PtrInt;
begin
  SetLength(Names, Count);
  SetLength(Values, Count);
  for i := 0 to Count - 1 do
  begin
    Names[i] := List[i].Name;
    Values[i] := List[i].Value;
  end;
end;

function TSynNameValue.ValueVariantOrNull(const aName: RawUtf8): variant;
var
  i: PtrInt;
begin
  i := Find(aName);
  if i < 0 then
    SetVariantNull(result{%H-})
  else
    RawUtf8ToVariant(List[i].Value, result);
end;

procedure TSynNameValue.AsDocVariant(out DocVariant: variant;
  ExtendedJson, ValueAsString, AllowVarDouble: boolean);
var
  ndx: PtrInt;
  dv: TDocVariantData absolute DocVariant;
begin
  if Count > 0 then
    begin
      dv.Init(JSON_OPTIONS_NAMEVALUE[ExtendedJson], dvObject);
      dv.SetCount(Count);
      dv.Capacity := Count;
      for ndx := 0 to Count - 1 do
      begin
        dv.Names[ndx] := List[ndx].Name;
        if ValueAsString or
           not GetNumericVariantFromJson(pointer(List[ndx].Value),
             TVarData(dv.Values[ndx]), AllowVarDouble) then
          RawUtf8ToVariant(List[ndx].Value, dv.Values[ndx]);
      end;
    end
  else
    TVarData(DocVariant).VType := varNull;
end;

function TSynNameValue.AsDocVariant(ExtendedJson, ValueAsString: boolean): variant;
begin
  AsDocVariant(result, ExtendedJson, ValueAsString);
end;

function TSynNameValue.MergeDocVariant(var DocVariant: variant;
  ValueAsString: boolean; ChangedProps: PVariant; ExtendedJson,
  AllowVarDouble: boolean): integer;
var
  dv: TDocVariantData absolute DocVariant;
  i, ndx: PtrInt;
  v: variant;
  intvalues: TRawUtf8Interning;
begin
  if dv.VarType <> DocVariantVType then
    TDocVariant.New(DocVariant, JSON_OPTIONS_NAMEVALUE[ExtendedJson]);
  if ChangedProps <> nil then
    TDocVariant.New(ChangedProps^, dv.Options);
  if dvoInternValues in dv.Options then
    intvalues := DocVariantType.InternValues
  else
    intvalues := nil;
  result := 0; // returns number of changed values
  for i := 0 to Count - 1 do
    if List[i].Name <> '' then
    begin
      VarClear(v{%H-});
      if ValueAsString or
         not GetNumericVariantFromJson(pointer(List[i].Value), TVarData(v),
               AllowVarDouble) then
        RawUtf8ToVariant(List[i].Value, v);
      ndx := dv.GetValueIndex(List[i].Name);
      if ndx < 0 then
        ndx := dv.InternalAdd(List[i].Name)
      else if FastVarDataComp(@v, @dv.Values[ndx], false) = 0 then
        continue; // value not changed -> skip
      if ChangedProps <> nil then
        PDocVariantData(ChangedProps)^.AddValue(List[i].Name, v);
      SetVariantByValue(v, dv.Values[ndx]);
      if intvalues <> nil then
        intvalues.UniqueVariant(dv.Values[ndx]);
      inc(result);
    end;
end;



{ TSynPersistentStoreJson }

procedure TSynPersistentStoreJson.AddJson(W: TTextWriter);
begin
  W.AddPropJsonString('name', fName);
end;

function TSynPersistentStoreJson.SaveToJson(reformat: TTextWriterJsonFormat): RawUtf8;
var
  W: TTextWriter;
begin
  W := TTextWriter.CreateOwnedStream(65536);
  try
    W.Add('{');
    AddJson(W);
    W.CancelLastComma;
    W.Add('}');
    W.SetText(result, reformat);
  finally
    W.Free;
  end;
end;



{ TSynCache }

constructor TSynCache.Create(aMaxCacheRamUsed: cardinal;
  aCaseSensitive: boolean; aTimeoutSeconds: cardinal);
begin
  inherited Create;
  fNameValue.Init(aCaseSensitive);
  fMaxRamUsed := aMaxCacheRamUsed;
  fTimeoutSeconds := aTimeoutSeconds;
end;

procedure TSynCache.ResetIfNeeded;
var
  tix: cardinal;
begin
  if fRamUsed > fMaxRamUsed then
    Reset;
  if fTimeoutSeconds > 0 then
  begin
    tix := GetTickCount64 shr 10;
    if fTimeoutTix > tix then
      Reset;
    fTimeoutTix := tix + fTimeoutSeconds;
  end;
end;

procedure TSynCache.Add(const aValue: RawUtf8; aTag: PtrInt);
begin
  if (self = nil) or
     (fFindLastKey = '') then
    exit;
  ResetIfNeeded;
  inc(fRamUsed, length(aValue));
  fNameValue.Add(fFindLastKey, aValue, aTag);
  fFindLastKey := '';
end;

function TSynCache.Find(const aKey: RawUtf8; aResultTag: PPtrInt): RawUtf8;
var
  ndx: integer;
begin
  result := '';
  if self = nil then
    exit;
  fFindLastKey := aKey;
  if aKey = '' then
    exit;
  ndx := fNameValue.Find(aKey);
  if ndx < 0 then
    exit;
  with fNameValue.List[ndx] do
  begin
    result := Value;
    if aResultTag <> nil then
      aResultTag^ := Tag;
  end;
end;

function TSynCache.AddOrUpdate(const aKey, aValue: RawUtf8; aTag: PtrInt): boolean;
var
  ndx: integer;
begin
  result := false;
  if self = nil then
    exit; // avoid GPF
  fSafe.Lock;
  try
    ResetIfNeeded;
    ndx := fNameValue.DynArray.FindHashedForAdding(aKey, result);
    with fNameValue.List[ndx] do
    begin
      Name := aKey;
      dec(fRamUsed, length(Value));
      Value := aValue;
      inc(fRamUsed, length(Value));
      Tag := aTag;
    end;
  finally
    fSafe.Unlock;
  end;
end;

function TSynCache.Reset: boolean;
begin
  result := false;
  if self = nil then
    exit; // avoid GPF
  fSafe.Lock;
  try
    if Count <> 0 then
    begin
      fNameValue.DynArray.Clear;
      fNameValue.DynArray.ReHash;
      result := true; // mark something was flushed
    end;
    fRamUsed := 0;
    fTimeoutTix := 0;
  finally
    fSafe.Unlock;
  end;
end;

function TSynCache.Count: integer;
begin
  if self = nil then
  begin
    result := 0;
    exit;
  end;
  fSafe.Lock;
  try
    result := fNameValue.Count;
  finally
    fSafe.Unlock;
  end;
end;


{ *********** JSON-aware TSynDictionary Storage }

{ TSynDictionary }

const // use fSafe.Padding[DIC_*] slots for Keys/Values place holders
  DIC_KEYCOUNT = 0;
  DIC_KEY = 1;
  DIC_VALUECOUNT = 2;
  DIC_VALUE = 3;
  DIC_TIMECOUNT = 4;
  DIC_TIMESEC = 5;
  DIC_TIMETIX = 6;

function TSynDictionary.KeyFullHash(const Elem): cardinal;
begin
  result := fKeys.Hasher.Hasher(0, @Elem, fKeys.Info.Cache.ItemSize);
end;

function TSynDictionary.KeyFullCompare(const A, B): integer;
var
  i: PtrInt;
begin
  for i := 0 to fKeys.Info.Cache.ItemSize - 1 do
  begin
    result := TByteArray(A)[i];
    dec(result, TByteArray(B)[i]); // in two steps for better asm generation
    if result <> 0 then
      exit;
  end;
  result := 0;
end;

constructor TSynDictionary.Create(aKeyTypeInfo, aValueTypeInfo: PRttiInfo;
  aKeyCaseInsensitive: boolean; aTimeoutSeconds: cardinal;
  aCompressAlgo: TAlgoCompress; aHasher: THasher);
begin
  inherited Create;
  fSafe.Padding[DIC_KEYCOUNT].VType := varInteger;    // Keys.Count integer
  fSafe.Padding[DIC_VALUECOUNT].VType := varInteger;  // Values.Count integer
  fSafe.Padding[DIC_KEY].VType := varUnknown;         // Key.Value pointer
  fSafe.Padding[DIC_VALUE].VType := varUnknown;       // Values.Value pointer
  fSafe.Padding[DIC_TIMECOUNT].VType := varInteger;   // Timeouts.Count integer
  fSafe.Padding[DIC_TIMESEC].VType := varInteger;     // Timeouts Seconds
  fSafe.Padding[DIC_TIMETIX].VType := varInteger;  // last GetTickCount64 shr 10
  fSafe.PaddingUsedCount := DIC_TIMETIX + 1;
  fKeys.Init(aKeyTypeInfo, fSafe.Padding[DIC_KEY].VAny, nil, nil, aHasher,
    @fSafe.Padding[DIC_KEYCOUNT].VInteger, aKeyCaseInsensitive);
  if not Assigned(fKeys.HashItem) then
    fKeys.EventHash := KeyFullHash;
  if not Assigned(fKeys.{$ifdef UNDIRECTDYNARRAY}InternalDynArray.{$endif}Compare) then
    fKeys.EventCompare := KeyFullCompare;
  fValues.Init(aValueTypeInfo, fSafe.Padding[DIC_VALUE].VAny,
    @fSafe.Padding[DIC_VALUECOUNT].VInteger);
  fTimeouts.Init(TypeInfo(TIntegerDynArray), fTimeOut,
    @fSafe.Padding[DIC_TIMECOUNT].VInteger);
  if aCompressAlgo = nil then
    aCompressAlgo := AlgoSynLZ;
  fCompressAlgo := aCompressAlgo;
  fSafe.Padding[DIC_TIMESEC].VInteger := aTimeoutSeconds;
end;

function TSynDictionary.ComputeNextTimeOut: cardinal;
begin
  result := fSafe.Padding[DIC_TIMESEC].VInteger;
  if result <> 0 then
    result := cardinal(GetTickCount64 shr 10) + result;
end;

function TSynDictionary.GetCapacity: integer;
begin
  if doSingleThreaded in fOptions then
    result := fKeys.Capacity
  else
  begin
    fSafe.Lock;
    result := fKeys.Capacity;
    fSafe.UnLock;
  end;
end;

procedure TSynDictionary.SetCapacity(const Value: integer);
begin
  if not (doSingleThreaded in fOptions) then
    fSafe.Lock;
  try
    fKeys.Capacity := Value;
    fValues.Capacity := Value;
    if fSafe.Padding[DIC_TIMESEC].VInteger > 0 then
      fTimeOuts.Capacity := Value;
  finally
    if not (doSingleThreaded in fOptions) then
      fSafe.UnLock;
  end;
end;

function TSynDictionary.GetTimeOutSeconds: cardinal;
begin
  result := fSafe.Padding[DIC_TIMESEC].VInteger;
end;

procedure TSynDictionary.SetTimeOutSeconds(Value: cardinal);
begin
  if not (doSingleThreaded in fOptions) then
    fSafe.Lock;
  try
    DeleteAll;
    fSafe.Padding[DIC_TIMESEC].VInteger := Value;
  finally
    if not (doSingleThreaded in fOptions) then
      fSafe.UnLock;
  end;
end;

procedure TSynDictionary.SetTimeouts;
var
  i: PtrInt;
  timeout: cardinal;
begin
  if fSafe.Padding[DIC_TIMESEC].VInteger = 0 then
    exit;
  fTimeOuts.Count := fSafe.Padding[DIC_KEYCOUNT].VInteger;
  timeout := ComputeNextTimeOut;
  for i := 0 to fSafe.Padding[DIC_TIMECOUNT].VInteger - 1 do
    fTimeOut[i] := timeout;
end;

function TSynDictionary.DeleteDeprecated: integer;
var
  i: PtrInt;
  now: cardinal;
begin
  result := 0;
  if (self = nil) or
     (fSafe.Padding[DIC_TIMECOUNT].VInteger = 0) or // no entry
     (fSafe.Padding[DIC_TIMESEC].VInteger = 0) then // nothing in fTimeOut[]
    exit;
  now := GetTickCount64 shr 10;
  if fSafe.Padding[DIC_TIMETIX].VInteger = integer(now) then
    exit; // no need to search more often than every second
  if not (doSingleThreaded in fOptions) then
    fSafe.Lock;
  try
    fSafe.Padding[DIC_TIMETIX].VInteger := now;
    for i := fSafe.Padding[DIC_TIMECOUNT].VInteger - 1 downto 0 do
      if (now > fTimeOut[i]) and
         (fTimeOut[i] <> 0) and
         (not Assigned(fOnCanDelete) or
          fOnCanDelete(fKeys.ItemPtr(i)^, fValues.ItemPtr(i)^, i)) then
      begin
        fKeys.Delete(i);
        fValues.Delete(i);
        fTimeOuts.Delete(i);
        inc(result);
      end;
    if result > 0 then
      fKeys.Rehash; // mandatory after fKeys.Delete(i)
  finally
    if not (doSingleThreaded in fOptions) then
      fSafe.UnLock;
  end;
end;

procedure TSynDictionary.DeleteAll;
begin
  if self = nil then
    exit;
  if not (doSingleThreaded in fOptions) then
    fSafe.Lock;
  try
    fKeys.Clear;
    fKeys.Hasher.Clear; // mandatory to avoid GPF
    fValues.Clear;
    if fSafe.Padding[DIC_TIMESEC].VInteger > 0 then
      fTimeOuts.Clear;
  finally
    if not (doSingleThreaded in fOptions) then
      fSafe.UnLock;
  end;
end;

destructor TSynDictionary.Destroy;
begin
  fKeys.Clear;
  fValues.Clear;
  inherited Destroy;
end;

function TSynDictionary.InternalAddUpdate(
  aKey, aValue: pointer; aUpdate: boolean): integer;
var
  added: boolean;
  tim: cardinal;
begin
  tim := ComputeNextTimeOut;
  result := fKeys.FindHashedForAdding(aKey^, added);
  if added then
  begin
    with fKeys{$ifdef UNDIRECTDYNARRAY}.InternalDynArray{$endif} do
      // fKey[result] := aKey;
      ItemCopy(aKey, PAnsiChar(Value^) + (result * Info.Cache.ItemSize));
    if fValues.Add(aValue^) <> result then
      raise ESynDictionary.CreateUtf8('%.Add fValues.Add', [self]);
    if tim <> 0 then
      fTimeOuts.Add(tim);
  end
  else if aUpdate then
  begin
    fValues.ItemCopyFrom(@aValue, result, {ClearBeforeCopy=}true);
    if tim <> 0 then
      fTimeOut[result] := tim;
  end
  else
    result := -1;
end;

function TSynDictionary.Add(const aKey, aValue): integer;
begin
  if doSingleThreaded in fOptions then
    result := InternalAddUpdate(@aKey, @aValue, {update=}false)
  else
  begin
    fSafe.Lock;
    try
      result := InternalAddUpdate(@aKey, @aValue, {update=}false)
    finally
      fSafe.UnLock;
    end;
  end;
end;

function TSynDictionary.AddOrUpdate(const aKey, aValue): integer;
begin
  if doSingleThreaded in fOptions then
    result := InternalAddUpdate(@aKey, @aValue, {update=}true)
  else
  begin
    fSafe.Lock;
    try
      result := InternalAddUpdate(@aKey, @aValue, {update=}true)
    finally
      fSafe.UnLock;
    end;
  end;
end;

function TSynDictionary.Clear(const aKey): integer;
begin
  if not (doSingleThreaded in fOptions) then
    fSafe.Lock;
  try
    result := fKeys.FindHashed(aKey);
    if result >= 0 then
    begin
      fValues.ItemClear(fValues.ItemPtr(result));
      if fSafe.Padding[DIC_TIMESEC].VInteger > 0 then
        fTimeOut[result] := 0;
    end;
  finally
    if not (doSingleThreaded in fOptions) then
      fSafe.UnLock;
  end;
end;

function TSynDictionary.Delete(const aKey): integer;
begin
  if not (doSingleThreaded in fOptions) then
    fSafe.Lock;
  try
    result := fKeys.FindHashedAndDelete(aKey);
    if result >= 0 then
    begin
      fValues.Delete(result);
      if fSafe.Padding[DIC_TIMESEC].VInteger > 0 then
        fTimeOuts.Delete(result);
    end;
  finally
    if not (doSingleThreaded in fOptions) then
      fSafe.UnLock;
  end;
end;

function TSynDictionary.DeleteAt(aIndex: integer): boolean;
begin
  if cardinal(aIndex) < cardinal(fSafe.Padding[DIC_KEYCOUNT].VInteger) then
    // use Delete(aKey) to have efficient hash table update
    result := Delete(fKeys.ItemPtr(aIndex)^) = aIndex
  else
    result := false;
end;

function TSynDictionary.InArray(const aKey, aArrayValue;
  aAction: TSynDictionaryInArray; aCompare: TDynArraySortCompare): boolean;
var
  nested: TDynArray;
  ndx: PtrInt;
  new: pointer;
begin
  result := false;
  if (fValues.Info.ArrayRtti = nil) or
     (fValues.Info.ArrayRtti.Kind <> rkDynArray) then
    raise ESynDictionary.CreateUtf8('%.Values: % items are not dynamic arrays',
      [self, fValues.Info.Name]);
  if not (doSingleThreaded in fOptions) then
    fSafe.Lock;
  try
    ndx := fKeys.FindHashed(aKey);
    if ndx < 0 then
      if aAction <> iaAddForced then
        exit
      else
      begin
        new := nil;
        ndx := Add(aKey, new);
      end;
    nested.InitRtti(fValues.Info.ArrayRtti, fValues.ItemPtr(ndx)^);
    nested.Compare := aCompare;
    case aAction of
      iaFind:
        result := nested.Find(aArrayValue) >= 0;
      iaFindAndDelete:
        result := nested.FindAndDelete(aArrayValue) >= 0;
      iaFindAndUpdate:
        result := nested.FindAndUpdate(aArrayValue) >= 0;
      iaFindAndAddIfNotExisting:
        result := nested.FindAndAddIfNotExisting(aArrayValue) >= 0;
      iaAdd, iaAddForced:
        result := nested.Add(aArrayValue) >= 0;
    end;
  finally
    if not (doSingleThreaded in fOptions) then
      fSafe.UnLock;
  end;
end;

function TSynDictionary.FindInArray(const aKey, aArrayValue;
  aCompare: TDynArraySortCompare): boolean;
begin
  result := InArray(aKey, aArrayValue, iaFind, aCompare);
end;

function TSynDictionary.FindKeyFromValue(const aValue;
  out aKey; aUpdateTimeOut: boolean): boolean;
var
  ndx: integer;
begin
  if not (doSingleThreaded in fOptions) then
    fSafe.Lock;
  try
    ndx := fValues.IndexOf(aValue); // use fast RTTI for value search
    result := ndx >= 0;
    if result then
    begin
      fKeys.ItemCopyAt(ndx, @aKey);
      if aUpdateTimeOut then
        SetTimeoutAtIndex(ndx);
    end;
  finally
    if not (doSingleThreaded in fOptions) then
      fSafe.UnLock;
  end;
end;

function TSynDictionary.DeleteInArray(const aKey, aArrayValue;
  aCompare: TDynArraySortCompare): boolean;
begin
  result := InArray(aKey, aArrayValue, iaFindAndDelete, aCompare);
end;

function TSynDictionary.UpdateInArray(const aKey, aArrayValue;
  aCompare: TDynArraySortCompare): boolean;
begin
  result := InArray(aKey, aArrayValue, iaFindAndUpdate, aCompare);
end;

function TSynDictionary.AddInArray(const aKey, aArrayValue;
  aCompare: TDynArraySortCompare): boolean;
begin
  result := InArray(aKey, aArrayValue, iaAdd, aCompare);
end;

function TSynDictionary.AddInArrayForced(const aKey, aArrayValue;
  aCompare: TDynArraySortCompare): boolean;
begin
  result := InArray(aKey, aArrayValue, iaAddForced, aCompare);
end;

function TSynDictionary.AddOnceInArray(const aKey, aArrayValue;
  aCompare: TDynArraySortCompare): boolean;
begin
  result := InArray(aKey, aArrayValue, iaFindAndAddIfNotExisting, aCompare);
end;

function TSynDictionary.Find(const aKey; aUpdateTimeOut: boolean): integer;
var
  tim: cardinal;
begin
  // caller is expected to call fSafe.Lock/Unlock
  if self = nil then
    result := -1
  else
    result := fKeys.FindHashed(aKey);
  if aUpdateTimeOut and
     (result >= 0) then
  begin
    tim := fSafe.Padding[DIC_TIMESEC].VInteger;
    if tim > 0 then // inlined fTimeout[result] := GetTimeout
      fTimeout[result] := cardinal(GetTickCount64 shr 10) + tim;
  end;
end;

function TSynDictionary.FindValue(const aKey; aUpdateTimeOut: boolean;
  aIndex: PInteger): pointer;
var
  ndx: PtrInt;
begin
  ndx := Find(aKey, aUpdateTimeOut);
  if aIndex <> nil then
    aIndex^ := ndx;
  if ndx < 0 then
    result := nil
  else
    result := PAnsiChar(fValues.Value^) + ndx * fValues.Info.Cache.ItemSize;
end;

function TSynDictionary.FindValueOrAdd(const aKey; var added: boolean;
  aIndex: PInteger): pointer;
var
  ndx: integer;
  tim: cardinal;
begin
  tim := fSafe.Padding[DIC_TIMESEC].VInteger; // inlined tim := GetTimeout
  if tim <> 0 then
    tim := cardinal(GetTickCount64 shr 10) + tim;
  ndx := fKeys.FindHashedForAdding(aKey, added);
  if added then
  begin
    fKeys{$ifdef UNDIRECTDYNARRAY}.InternalDynArray{$endif}.
      ItemCopyFrom(@aKey, ndx); // fKey[i] := aKey
    fValues.Count := ndx + 1; // reserve new place for associated value
    if tim > 0 then
      fTimeOuts.Add(tim);
  end
  else if tim > 0 then
    fTimeOut[ndx] := tim;
  if aIndex <> nil then
    aIndex^ := ndx;
  result := fValues.ItemPtr(ndx);
end;

function TSynDictionary.FindAndCopy(const aKey;
  var aValue; aUpdateTimeOut: boolean): boolean;
var
  ndx: integer;
begin
  if not (doSingleThreaded in fOptions) then
    fSafe.Lock;
  try
    ndx := Find(aKey, aUpdateTimeOut);
    if ndx >= 0 then
    begin
      fValues.ItemCopyAt(ndx, @aValue);
      result := true;
    end
    else
      result := false;
  finally
    if not (doSingleThreaded in fOptions) then
      fSafe.UnLock;
  end;
end;

function TSynDictionary.FindAndExtract(const aKey; var aValue): boolean;
var
  ndx: integer;
begin
  if not (doSingleThreaded in fOptions) then
    fSafe.Lock;
  try
    ndx := fKeys.FindHashedAndDelete(aKey);
    if ndx >= 0 then
    begin
      fValues.ItemMoveTo(ndx, @aValue); // faster than ItemCopyAt()
      fValues.Delete(ndx);
      if fSafe.Padding[DIC_TIMESEC].VInteger > 0 then
        fTimeOuts.Delete(ndx);
      result := true;
    end
    else
      result := false;
  finally
    if not (doSingleThreaded in fOptions) then
      fSafe.UnLock;
  end;
end;

function TSynDictionary.Exists(const aKey): boolean;
begin
  if doSingleThreaded in fOptions then
  begin
    result := fKeys.FindHashed(aKey) >= 0;
    exit;
  end;
  fSafe.Lock;
  try
    result := fKeys.FindHashed(aKey) >= 0;
  finally
    fSafe.UnLock;
  end;
end;

function TSynDictionary.ExistsValue(
  const aValue; aCompare: TDynArraySortCompare): boolean;
begin
  if not (doSingleThreaded in fOptions) then
    fSafe.Lock;
  try
    result := fValues.Find(aValue, aCompare) >= 0;
  finally
    if not (doSingleThreaded in fOptions) then
      fSafe.UnLock;
  end;
end;

procedure TSynDictionary.CopyValues(out Dest; ObjArrayByRef: boolean);
begin
  if not (doSingleThreaded in fOptions) then
    fSafe.Lock;
  try
    fValues.CopyTo(Dest, ObjArrayByRef);
  finally
    if not (doSingleThreaded in fOptions) then
      fSafe.UnLock;
  end;
end;

function TSynDictionary.ForEach(const OnEach: TOnSynDictionary;
  Opaque: pointer): integer;
var
  k, v: PAnsiChar;
  i, n, ks, vs: PtrInt;
begin
  result := 0;
  if not (doSingleThreaded in fOptions) then
    fSafe.Lock;
  try
    n := fSafe.Padding[DIC_KEYCOUNT].VInteger;
    if (n = 0) or
       not Assigned(OnEach) then
      exit;
    k := fKeys.Value^;
    ks := fKeys.Info.Cache.ItemSize;
    v := fValues.Value^;
    vs := fValues.Info.Cache.ItemSize;
    for i := 0 to n - 1 do
    begin
      inc(result);
      if not OnEach(k^, v^, i, n, Opaque) then
        break;
      inc(k, ks);
      inc(v, vs);
    end;
  finally
    if not (doSingleThreaded in fOptions) then
      fSafe.UnLock;
  end;
end;

function TSynDictionary.ForEach(const OnMatch: TOnSynDictionary;
  KeyCompare, ValueCompare: TDynArraySortCompare; const aKey, aValue;
  Opaque: pointer): integer;
var
  k, v: PAnsiChar;
  i, n, ks, vs: PtrInt;
begin
  if not (doSingleThreaded in fOptions) then
    fSafe.Lock;
  try
    result := 0;
    if not Assigned(OnMatch) or
       not (Assigned(KeyCompare) or
            Assigned(ValueCompare)) then
      exit;
    n := fSafe.Padding[DIC_KEYCOUNT].VInteger;
    k := fKeys.Value^;
    ks := fKeys.Info.Cache.ItemSize;
    v := fValues.Value^;
    vs := fValues.Info.Cache.ItemSize;
    for i := 0 to n - 1 do
    begin
      if (Assigned(KeyCompare) and
          (KeyCompare(k^, aKey) = 0)) or
         (Assigned(ValueCompare) and
          (ValueCompare(v^, aValue) = 0)) then
      begin
        inc(result);
        if not OnMatch(k^, v^, i, n, Opaque) then
          break;
      end;
      inc(k, ks);
      inc(v, vs);
    end;
  finally
    if not (doSingleThreaded in fOptions) then
      fSafe.UnLock;
  end;
end;

procedure TSynDictionary.SetTimeoutAtIndex(aIndex: integer);
var
  tim: cardinal;
begin
  if cardinal(aIndex) >= cardinal(fSafe.Padding[DIC_KEYCOUNT].VInteger) then
    exit;
  tim := fSafe.Padding[DIC_TIMESEC].VInteger;
  if tim > 0 then
    fTimeOut[aIndex] := cardinal(GetTickCount64 shr 10) + tim;
end;

function TSynDictionary.Count: integer;
begin
  result := fSafe.LockedInt64[DIC_KEYCOUNT];
end;

function TSynDictionary.RawCount: integer;
begin
  result := fSafe.Padding[DIC_KEYCOUNT].VInteger;
end;

procedure TSynDictionary.SaveToJson(W: TTextWriter; EnumSetsAsText: boolean);
var
  k, v: RawUtf8;
begin
  if not (doSingleThreaded in fOptions) then
    fSafe.Lock;
  try
    if fSafe.Padding[DIC_KEYCOUNT].VInteger > 0 then
    begin
      fKeys{$ifdef UNDIRECTDYNARRAY}.InternalDynArray{$endif}.
        SaveToJson(k, EnumSetsAsText);
      fValues.SaveToJson(v, EnumSetsAsText);
    end;
  finally
    if not (doSingleThreaded in fOptions) then
      fSafe.UnLock;
  end;
  W.AddJsonArraysAsJsonObject(pointer(k), pointer(v));
end;

function TSynDictionary.SaveToJson(EnumSetsAsText: boolean): RawUtf8;
var
  W: TTextWriter;
  temp: TTextWriterStackBuffer;
begin
  W := TTextWriter.CreateOwnedStream(temp) as TTextWriter;
  try
    SaveToJson(W, EnumSetsAsText);
    W.SetText(result);
  finally
    W.Free;
  end;
end;

function TSynDictionary.SaveValuesToJson(EnumSetsAsText: boolean): RawUtf8;
begin
  if not (doSingleThreaded in fOptions) then
    fSafe.Lock;
  try
    fValues.SaveToJson(result, EnumSetsAsText);
  finally
    if not (doSingleThreaded in fOptions) then
      fSafe.UnLock;
  end;
end;

function TSynDictionary.LoadFromJson(const Json: RawUtf8;
  CustomVariantOptions: PDocVariantOptions): boolean;
begin
  // pointer(Json) is not modified in-place thanks to JsonObjectAsJsonArrays()
  result := LoadFromJson(pointer(Json), CustomVariantOptions);
end;

function TSynDictionary.LoadFromJson(Json: PUtf8Char;
  CustomVariantOptions: PDocVariantOptions): boolean;
var
  k, v: RawUtf8; // private copy of the Json input, expanded as Keys/Values arrays
  n: integer;
begin
  result := false;
  n := JsonObjectAsJsonArrays(Json, k, v);
  if n <= 0 then
    exit;
  if not (doSingleThreaded in fOptions) then
    fSafe.Lock;
  try
    if (fKeys.LoadFromJson(pointer(k), nil, CustomVariantOptions) <> nil) and
       (fKeys.Count = n) and
       (fValues.LoadFromJson(pointer(v), nil, CustomVariantOptions) <> nil) and
       (fValues.Count = n) then
      begin
        SetTimeouts;
        fKeys.Rehash; // warning: duplicated keys won't be identified
        result := true;
      end;
  finally
    if not (doSingleThreaded in fOptions) then
      fSafe.UnLock;
  end;
end;

function TSynDictionary.LoadFromBinary(const binary: RawByteString): boolean;
var
  plain: RawByteString;
  rdr: TFastReader;
  n: integer;
begin
  result := false;
  plain := fCompressAlgo.Decompress(binary);
  if plain = '' then
    exit;
  rdr.Init(plain);
  if not (doSingleThreaded in fOptions) then
    fSafe.Lock;
  try
    try
      RTTI_BINARYLOAD[rkDynArray](fKeys.Value, rdr, fKeys.Info.Info);
      RTTI_BINARYLOAD[rkDynArray](fValues.Value, rdr, fValues.Info.Info);
      n := fKeys.Capacity;
      if n = fValues.Capacity then
      begin
        // RTTI_BINARYLOAD[rkDynArray]() did not set the external count
        fSafe.Padding[DIC_KEYCOUNT].VInteger := n;
        fSafe.Padding[DIC_VALUECOUNT].VInteger := n;      
        SetTimeouts;  // set ComputeNextTimeOut for all items
        fKeys.ReHash; // optimistic: input from safe TSynDictionary.SaveToBinary
        result := true;
      end;
    except
      result := false;
    end;
  finally
    if not (doSingleThreaded in fOptions) then
      fSafe.UnLock;
  end;
end;

class function TSynDictionary.OnCanDeleteSynPersistentLock(const aKey, aValue;
  aIndex: integer): boolean;
begin
  result := not TSynPersistentLock(aValue).Safe^.IsLocked;
end;

class function TSynDictionary.OnCanDeleteSynPersistentLocked(const aKey, aValue;
  aIndex: integer): boolean;
begin
  result := not TSynPersistentLock(aValue).Safe.IsLocked;
end;

function TSynDictionary.SaveToBinary(NoCompression: boolean;
  Algo: TAlgoCompress): RawByteString;
var
  tmp: TTextWriterStackBuffer;
  W: TBufferWriter;
begin
  if not (doSingleThreaded in fOptions) then
    fSafe.Lock;
  try
    result := '';
    if fSafe.Padding[DIC_KEYCOUNT].VInteger = 0 then
      exit;
    W := TBufferWriter.Create(tmp{%H-});
    try
      RTTI_BINARYSAVE[rkDynArray](fKeys.Value, W, fKeys.Info.Info);
      RTTI_BINARYSAVE[rkDynArray](fValues.Value, W, fValues.Info.Info);
      result := W.FlushAndCompress(NoCompression, Algo);
    finally
      W.Free;
    end;
  finally
    if not (doSingleThreaded in fOptions) then
      fSafe.UnLock;
  end;
end;



{ ********** Custom JSON Serialization }

{ TRttiJson }

function _New_ObjectList(Rtti: TRttiCustom): pointer;
begin
  result := TObjectListClass(Rtti.ValueClass).Create;
end;

function _New_InterfacedObjectWithCustomCreate(Rtti: TRttiCustom): pointer;
begin
  result := TInterfacedObjectWithCustomCreateClass(Rtti.ValueClass).Create;
end;

function _New_PersistentWithCustomCreate(Rtti: TRttiCustom): pointer;
begin
  result := TPersistentWithCustomCreateClass(Rtti.ValueClass).Create;
end;

function _New_Component(Rtti: TRttiCustom): pointer;
begin
  result := TComponentClass(Rtti.ValueClass).Create(nil);
end;

function _New_ObjectWithCustomCreate(Rtti: TRttiCustom): pointer;
begin
  result := TObjectWithCustomCreateClass(Rtti.ValueClass).Create;
end;

function _New_SynObjectList(Rtti: TRttiCustom): pointer;
begin
  result := TSynObjectListClass(Rtti.ValueClass).Create({ownobjects=}true);
end;

function _New_SynLocked(Rtti: TRttiCustom): pointer;
begin
  result := TSynLockedClass(Rtti.ValueClass).Create;
end;

function _New_InterfacedCollection(Rtti: TRttiCustom): pointer;
begin
  result := TInterfacedCollectionClass(Rtti.ValueClass).Create;
end;

function _New_Collection(Rtti: TRttiCustom): pointer;
begin
  if Rtti.CollectionItem = nil then
    raise ERttiException.CreateUtf8('% with CollectionItem=nil: please call ' +
      'Rtti.RegisterCollection()', [Rtti.ValueClass]);
  result := TCollectionClass(Rtti.ValueClass).Create(Rtti.CollectionItem);
end;

function _New_CollectionItem(Rtti: TRttiCustom): pointer;
begin
  result := TCollectionItemClass(Rtti.ValueClass).Create(nil);
end;

function _New_List(Rtti: TRttiCustom): pointer;
begin
  result := TListClass(Rtti.ValueClass).Create;
end;

function _New_Object(Rtti: TRttiCustom): pointer;
begin
  result := Rtti.ValueClass.Create; // non-virtual TObject.Create constructor
end;

function _BC_RawByteString(A, B: PPUtf8Char; Info: PRttiInfo;
  out Compared: integer): PtrInt;
begin
  {$ifdef CPUINTEL}
  compared := SortDynArrayAnsiString(A^, B^); // i386/x86_64 asm uses length
  {$else}
  compared := SortDynArrayRawByteString(A^, B^); // will use length not #0
  {$endif CPUINTEL}
  result := SizeOf(pointer);
end;

function TRttiJson.SetParserType(aParser: TRttiParserType;
  aParserComplex: TRttiParserComplexType): TRttiCustom;
var
  C: TClass;
begin
  // set Name and Flags from Props[]
  inherited SetParserType(aParser, aParserComplex);
  // set comparison functions
  if rcfObjArray in fFlags then
  begin
    fCompare[true] := _BC_ObjArray;
    fCompare[false] := _BCI_ObjArray;
  end
  else
  begin
    fCompare[true] := RTTI_COMPARE[true][Kind];
    fCompare[false] := RTTI_COMPARE[false][Kind];
    if Kind = rkLString then
      // RTTI_COMPARE[rkLString] is StrCmp/StrICmp which is mostly fine
      if Cache.CodePage >= CP_RAWBLOB then
      begin
        // should use RawByteString length, and ignore any #0
        fCompare[true] := @_BC_RawByteString;
        fCompare[false] := @_BC_RawByteString;
      end
      else if Cache.CodePage = CP_UTF16 then
      begin
        // RawUnicode expects _BC_WString=StrCompW and _BCI_WString=StrICompW
        fCompare[true] := RTTI_COMPARE[true][rkWString];
        fCompare[false] := RTTI_COMPARE[false][rkWString];
      end;
  end;
  // set class serialization and initialization
  if aParser = ptClass then
  begin
    // default JSON serialization of published props
    fJsonSave := @_JS_RttiCustom;
    fJsonLoad := @_JL_RttiCustom;
    // prepare efficient ClassNewInstance() and recognize most parents
    C := fValueClass;
    repeat
      if C = TObjectList then
      begin
        fClassNewInstance := @_New_ObjectList;
        fJsonSave := @_JS_TObjectList;
        fJsonLoad := @_JL_TObjectList;
      end
      else if C = TInterfacedObjectWithCustomCreate then
        fClassNewInstance := @_New_InterfacedObjectWithCustomCreate
      else if C = TPersistentWithCustomCreate then
        fClassNewInstance := @_New_PersistentWithCustomCreate
      else if C = TObjectWithCustomCreate then
      begin
        fClassNewInstance := @_New_ObjectWithCustomCreate;
        // allow any kind of customization for TObjectWithCustomCreate children
        TCCHookClass(fValueClass).RttiCustomSetParser(self);
      end
      else if C = TSynObjectList then
      begin
        fClassNewInstance := @_New_SynObjectList;
        fJsonSave := @_JS_TSynObjectList;
        fJsonLoad := @_JL_TSynObjectList;
      end
      else if C = TSynLocked then
        fClassNewInstance := @_New_SynLocked
      else if C = TComponent then
        fClassNewInstance := @_New_Component
      else if C = TInterfacedCollection then
      begin
        if fValueClass <> C then
        begin
          fCollectionItem := TInterfacedCollectionClass(fValueClass).GetClass;
          fCollectionItemRtti := Rtti.RegisterClass(fCollectionItem);
        end;
        fClassNewInstance := @_New_InterfacedCollection;
        fJsonSave := @_JS_TCollection;
        fJsonLoad := @_JL_TCollection;
      end
      else if C = TCollection then
      begin
        fClassNewInstance := @_New_Collection;
        fJsonSave := @_JS_TCollection;
        fJsonLoad := @_JL_TCollection;
      end
      else if C = TCollectionItem then
        fClassNewInstance := @_New_CollectionItem
      else if C = TList then
        fClassNewInstance := @_New_List
      else if C = TObject then
        fClassNewInstance := @_New_Object
      else
      begin
        if C = TSynList then
          fJsonSave := @_JS_TSynList
        else if C = TRawUtf8List then
        begin
          fJsonSave := @_JS_TRawUtf8List;
          fJsonLoad := @_JL_TRawUtf8List;
        end;
        C := C.ClassParent;
        continue;
      end;
      break;
    until false;
    case fValueRtlClass of
      vcStrings:
        begin
          fJsonSave := @_JS_TStrings;
          fJsonLoad := @_JL_TStrings;
        end;
      vcList:
        fJsonSave := @_JS_TList;
    end;
  end
  else if rcfBinary in Flags then
  begin
    fJsonSave := @_JS_Binary;
    fJsonLoad := @_JL_Binary;
  end
  else
  begin
    // default well-known serialization
    fJsonSave := PTC_JSONSAVE[aParserComplex];
    if not Assigned(fJsonSave) then
      fJsonSave := PT_JSONSAVE[aParser];
    fJsonLoad := PT_JSONLOAD[aParser];
    // rkRecordTypes serialization with proper fields RTTI
    if not Assigned(fJsonSave) and
       (Flags * [rcfWithoutRtti, rcfHasNestedProperties] <> []) then
      fJsonSave := @_JS_RttiCustom;
   if not Assigned(fJsonLoad) and
      (Flags * [rcfWithoutRtti, rcfHasNestedProperties] <> []) then
    fJsonLoad := @_JL_RttiCustom
  end;
  // TRttiJson.RegisterCustomSerializer() custom callbacks have priority
  if Assigned(fJsonWriter.Code) then
    fJsonSave := @_JS_RttiCustom;
  if Assigned(fJsonReader.Code) then
    fJsonLoad := @_JL_RttiCustom;
  result := self;
end;

function TRttiJson.ParseNewInstance(var Context: TJsonParserContext): TObject;
begin
  result := fClassNewInstance(self);
  TRttiJsonLoad(fJsonLoad)(@result, Context);
  if not Context.Valid then
    FreeAndNil(result);
end;

function TRttiJson.ValueCompare(Data, Other: pointer; CaseInsensitive: boolean): integer;
begin
  if Assigned(fCompare[CaseInsensitive]) then
    fCompare[CaseInsensitive](Data, Other, Info, result)
  else
    result := ComparePointer(Data, Other);
end;

function TRttiJson.ValueToVariant(Data: pointer; out Dest: TVarData): PtrInt;
label
  fro;
begin
  // see TRttiCustomProp.GetValueDirect
  PCardinal(@Dest.VType)^ := Cache.RttiVarDataVType;
  case Cache.RttiVarDataVType of
    varInt64, varBoolean:
      // rkInteger, rkBool using VInt64 for proper cardinal support
fro:  Dest.VInt64 := FromRttiOrd(Cache.RttiOrd, Data);
    varWord64:
      // rkInt64, rkQWord
      begin
        if not (rcfQWord in Cache.Flags) then
          PCardinal(@Dest.VType)^ := varInt64; // fix VType
        Dest.VInt64 := PInt64(Data)^;
      end;
    varDouble, varCurrency:
      Dest.VInt64 := PInt64(Data)^;
    varString:
      // rkString
      begin
        Dest.VAny := nil; // avoid GPF
        RawByteString(Dest.VAny) := PRawByteString(Data)^;
      end;
    varOleStr:
      // rkWString
      begin
        Dest.VAny := nil; // avoid GPF
        WideString(Dest.VAny) := PWideString(Data)^;
      end;
    {$ifdef HASVARUSTRING}
    varUString:
      // rkUString
      begin
        Dest.VAny := nil; // avoid GPF
        UnicodeString(Dest.VAny) := PUnicodeString(Data)^;
      end;
    {$endif HASVARUSTRING}
    varVariant:
      // rkVariant
      SetVariantByValue(PVariant(Data)^, PVariant(@Dest)^);
    varUnknown:
      // rkChar, rkWChar, rkSString converted into temporary RawUtf8
      begin
        PCardinal(@Dest.VType)^ := varString;
        Dest.VAny := nil; // avoid GPF
        Info.StringToUtf8(Data, RawUtf8(Dest.VAny));
      end;
   else
     case Cache.Kind of
       rkEnumeration, rkSet:
         begin
           PCardinal(@Dest.VType)^ := varInt64;
           goto fro;
         end;
     else
       raise EDocVariant.CreateUtf8(
         'Unsupported %.InitArrayFrom(%)', [self, ToText(Cache.Kind)^]);
     end;
  end;
  result := Cache.ItemSize;
end;

procedure TRttiJson.ValueLoadJson(Data: pointer; var Json: PUtf8Char;
  EndOfObject: PUtf8Char; ParserOptions: TJsonParserOptions;
  CustomVariantOptions: PDocVariantOptions; ObjectListItemClass: TClass);
var
  ctxt: TJsonParserContext;
begin
  if Assigned(self) then
  begin
    ctxt.Init(
      Json, self, ParserOptions, CustomVariantOptions, ObjectListItemClass);
    if Assigned(fJsonLoad) then
      // efficient direct Json parsing
      TRttiJsonLoad(fJsonLoad)(Data, ctxt)
    else
      // try if binary serialization was used
      ctxt.Valid := ctxt.ParseNext and
            (Ctxt.Value <> nil) and
            (PCardinal(Ctxt.Value)^ and $ffffff = JSON_BASE64_MAGIC_C) and
            BinaryLoadBase64(pointer(Ctxt.Value + 3), Ctxt.ValueLen - 3,
              Data, Ctxt.Info.Info, {uri=}false, rkAllTypes, {withcrc=}false);
    if ctxt.Valid then
      Json := ctxt.Json
    else
      Json := nil;
  end
  else
    Json := nil;
end;

procedure TRttiJson.RawSaveJson(Data: pointer; const Ctxt: TJsonSaveContext);
begin
  TRttiJsonSave(fJsonSave)(Data, Ctxt);
end;

procedure TRttiJson.RawLoadJson(Data: pointer; var Ctxt: TJsonParserContext);
begin
  TRttiJsonLoad(fJsonLoad)(Data, Ctxt);
end;

class function TRttiJson.Find(Info: PRttiInfo): TRttiJson;
begin
  result := pointer(Rtti.Find(Info));
end;

class function TRttiJson.RegisterCustomSerializer(Info: PRttiInfo;
  const Reader: TOnRttiJsonRead; const Writer: TOnRttiJsonWrite): TRttiJson;
begin
  result := Rtti.RegisterType(Info) as TRttiJson;
  // (re)set fJsonSave/fJsonLoad
  result.fJsonWriter := TMethod(Writer);
  result.fJsonReader := TMethod(Reader);
  if result.Kind <> rkDynArray then // Reader/Writer are for items, not array
    result.SetParserType(result.Parser, result.ParserComplex);
end;

class function TRttiJson.RegisterCustomSerializerClass(ObjectClass: TClass;
  const Reader: TOnClassJsonRead; const Writer: TOnClassJsonWrite): TRttiJson;
begin
  // without {$M+} ObjectClasss.ClassInfo=nil -> ensure fake RTTI is available
  result := Rtti.RegisterClass(ObjectClass) as TRttiJson;
  result.fJsonWriter := TMethod(Writer);
  result.fJsonReader := TMethod(Reader);
  result.SetParserType(ptClass, pctNone);
end;

class function TRttiJson.UnRegisterCustomSerializer(Info: PRttiInfo): TRttiJson;
begin
  result := Rtti.RegisterType(Info) as TRttiJson;
  result.fJsonWriter.Code := nil; // force reset of the JSON serialization
  result.fJsonReader.Code := nil;
  if result.Kind <> rkDynArray then // Reader/Writer are for items, not array
    result.SetParserType(result.Parser, result.ParserComplex);
end;

class function TRttiJson.UnRegisterCustomSerializerClass(ObjectClass: TClass): TRttiJson;
begin
  // without {$M+} ObjectClasss.ClassInfo=nil -> ensure fake RTTI is available
  result := Rtti.RegisterClass(ObjectClass) as TRttiJson;
  result.fJsonWriter.Code := nil; // force reset of the JSON serialization
  result.fJsonReader.Code := nil;
  result.SetParserType(result.Parser, result.ParserComplex);
end;

class function TRttiJson.RegisterFromText(DynArrayOrRecord: PRttiInfo;
  const RttiDefinition: RawUtf8;
  IncludeReadOptions: TJsonParserOptions;
  IncludeWriteOptions: TTextWriterWriteObjectOptions): TRttiJson;
begin
  result := Rtti.RegisterFromText(DynArrayOrRecord, RttiDefinition) as TRttiJson;
  result.fIncludeReadOptions := IncludeReadOptions;
  result.fIncludeWriteOptions := IncludeWriteOptions;
end;


procedure _GetDataFromJson(Data: pointer; var Json: PUtf8Char;
  EndOfObject: PUtf8Char; TypeInfo: PRttiInfo;
  CustomVariantOptions: PDocVariantOptions; Tolerant: boolean);
begin
  TRttiJson(Rtti.RegisterType(TypeInfo)).ValueLoadJson(Data, Json, EndOfObject,
    JSONPARSER_DEFAULTORTOLERANTOPTIONS[Tolerant], CustomVariantOptions);
end;


{ ********** JSON Serialization Wrapper Functions }

procedure SaveJson(const Value; TypeInfo: PRttiInfo; Options: TTextWriterOptions;
  var result: RawUtf8);
var
  temp: TTextWriterStackBuffer;
begin
  with TTextWriter.CreateOwnedStream(temp) do
  try
    CustomOptions := CustomOptions + Options;
    AddTypedJson(@Value, TypeInfo);
    SetText(result);
  finally
    Free;
  end;
end;

function SaveJson(const Value; TypeInfo: PRttiInfo; EnumSetsAsText: boolean): RawUtf8;
begin
  SaveJson(Value, TypeInfo, TEXTWRITEROPTIONS_SETASTEXT[EnumSetsAsText], result);
end;

function RecordSaveJson(const Rec; TypeInfo: PRttiInfo;
  EnumSetsAsText: boolean): RawUtf8;
begin
  if (TypeInfo <> nil) and
     (TypeInfo^.Kind in rkRecordTypes) then
    SaveJson(Rec, TypeInfo, TEXTWRITEROPTIONS_SETASTEXT[EnumSetsAsText], result)
  else
    result := NULL_STR_VAR;
end;

function DynArraySaveJson(const Value; TypeInfo: PRttiInfo;
  EnumSetsAsText: boolean): RawUtf8;
begin
  if (TypeInfo = nil) or
     (TypeInfo^.Kind <> rkDynArray) then
    result := NULL_STR_VAR
  else if pointer(Value) = nil then
    result := '[]'
  else
    SaveJson(Value, TypeInfo, TEXTWRITEROPTIONS_SETASTEXT[EnumSetsAsText], result);
end;

function DynArrayBlobSaveJson(TypeInfo: PRttiInfo; BlobValue: pointer): RawUtf8;
var
  DynArray: TDynArray;
  Value: pointer; // decode BlobValue into a temporary dynamic array
  temp: TTextWriterStackBuffer;
begin
  Value := nil;
  DynArray.Init(TypeInfo, Value);
  try
    if DynArray.LoadFrom(BlobValue) = nil then
      result := ''
    else
      with TTextWriter.CreateOwnedStream(temp) do
      try
        AddDynArrayJson(DynArray);
        SetText(result);
      finally
        Free;
      end;
  finally
    DynArray.Clear; // release temporary memory
  end;
end;

function ObjectsToJson(const Names: array of RawUtf8;
  const Values: array of TObject;
  Options: TTextWriterWriteObjectOptions): RawUtf8;
var
  i, n: PtrInt;
  temp: TTextWriterStackBuffer;
begin
  with TTextWriter.CreateOwnedStream(temp) do
  try
    n := high(Names);
    BlockBegin('{', Options);
    i := 0;
    if i <= high(Values) then
      repeat
        if i <= n then
          AddFieldName(Names[i])
        else if Values[i] = nil then
          AddFieldName(SmallUInt32Utf8[i])
        else
          AddPropName(ClassNameShort(Values[i])^);
        WriteObject(Values[i], Options);
        if i = high(Values) then
          break;
        BlockAfterItem(Options);
        inc(i);
      until false;
    CancelLastComma;
    BlockEnd('}', Options);
    SetText(result);
  finally
    Free;
  end;
end;

function ObjectToJsonFile(Value: TObject; const JsonFile: TFileName;
  Options: TTextWriterWriteObjectOptions): boolean;
var
  humanread: boolean;
  json: RawUtf8;
begin
  humanread := woHumanReadable in Options;
  if humanread and
     (woHumanReadableEnumSetAsComment in Options) then
    humanread := false
  else
    // JsonReformat() erases comments
    exclude(Options, woHumanReadable);
  json := ObjectToJson(Value, Options);
  if humanread then
    // woHumanReadable not working with custom JSON serializers, e.g. T*ObjArray
    // TODO: check if this is always the case with our mORMot2 new serialization
    result := JsonBufferReformatToFile(pointer(json), JsonFile)
  else
    result := FileFromString(json, JsonFile);
end;

function ObjectToJsonDebug(Value: TObject;
  Options: TTextWriterWriteObjectOptions): RawUtf8;
begin
  // our JSON serialization detects and serialize Exception.Message
  result := ObjectToJson(Value, Options);
end;

function LoadJson(var Value; Json: PUtf8Char; TypeInfo: PRttiInfo;
  EndOfObject: PUtf8Char; CustomVariantOptions: PDocVariantOptions;
  Tolerant: boolean): PUtf8Char;
begin
  TRttiJson(Rtti.RegisterType(TypeInfo)).ValueLoadJson(@Value, Json, EndOfObject,
    JSONPARSER_DEFAULTORTOLERANTOPTIONS[Tolerant], CustomVariantOptions);
  result := Json;
end;

function RecordLoadJson(var Rec; Json: PUtf8Char; TypeInfo: PRttiInfo;
  EndOfObject: PUtf8Char; CustomVariantOptions: PDocVariantOptions;
  Tolerant: boolean): PUtf8Char;
begin
  if (TypeInfo = nil) or
     not (TypeInfo.Kind in rkRecordTypes) then
    raise EJsonException.CreateUtf8('RecordLoadJson: % is not a record',
      [TypeInfo.Name]);
  TRttiJson(Rtti.RegisterType(TypeInfo)).ValueLoadJson(@Rec, Json, EndOfObject,
      JSONPARSER_DEFAULTORTOLERANTOPTIONS[Tolerant], CustomVariantOptions);
  result := Json;
end;

function RecordLoadJson(var Rec; const Json: RawUtf8; TypeInfo: PRttiInfo;
  CustomVariantOptions: PDocVariantOptions; Tolerant: boolean): boolean;
var
  tmp: TSynTempBuffer;
begin
  tmp.Init(Json); // make private copy before in-place decoding
  try
    result := RecordLoadJson(Rec, tmp.buf, TypeInfo, nil,
      CustomVariantOptions, Tolerant) <> nil;
  finally
    tmp.Done;
  end;
end;

function DynArrayLoadJson(var Value; Json: PUtf8Char; TypeInfo: PRttiInfo;
  EndOfObject: PUtf8Char; CustomVariantOptions: PDocVariantOptions;
  Tolerant: boolean): PUtf8Char;
begin
  if (TypeInfo = nil) or
     (TypeInfo.Kind <> rkDynArray) then
    raise EJsonException.CreateUtf8('DynArrayLoadJson: % is not a dynamic array',
      [TypeInfo.Name]);
  TRttiJson(Rtti.RegisterType(TypeInfo)).ValueLoadJson(@Value, Json, EndOfObject,
    JSONPARSER_DEFAULTORTOLERANTOPTIONS[Tolerant], CustomVariantOptions);
  result := Json;
end;

function DynArrayLoadJson(var Value; const Json: RawUtf8; TypeInfo: PRttiInfo;
  CustomVariantOptions: PDocVariantOptions; Tolerant: boolean): boolean;
var
  tmp: TSynTempBuffer;
begin
  tmp.Init(Json); // make private copy before in-place decoding
  try
    result := DynArrayLoadJson(Value, tmp.buf, TypeInfo, nil,
      CustomVariantOptions, Tolerant) <> nil;
  finally
    tmp.Done;
  end;
end;

function JsonToObject(var ObjectInstance; From: PUtf8Char; out Valid: boolean;
  TObjectListItemClass: TClass; Options: TJsonParserOptions): PUtf8Char;
var
  ctxt: TJsonParserContext;
begin
  if pointer(ObjectInstance) = nil then
    raise ERttiException.Create('JsonToObject(nil)');
  ctxt.Init(From, Rtti.RegisterClass(TObject(ObjectInstance)), Options,
    nil, TObjectListItemClass);
  TRttiJsonLoad(Ctxt.Info.JsonLoad)(@ObjectInstance, ctxt);
  Valid := ctxt.Valid;
  result := ctxt.Json;
end;

function JsonSettingsToObject(var InitialJsonContent: RawUtf8;
  Instance: TObject): boolean;
var
  tmp: TSynTempBuffer;
begin
  result := false;
  if InitialJsonContent = '' then
    exit;
  tmp.Init(InitialJsonContent);
  try
    RemoveCommentsFromJson(tmp.buf);
    JsonToObject(Instance, tmp.buf, result, nil, JSONPARSER_TOLERANTOPTIONS);
    if not result then
      InitialJsonContent := '';
  finally
    tmp.Done;
  end;
end;

function ObjectLoadJson(var ObjectInstance; const Json: RawUtf8;
  TObjectListItemClass: TClass; Options: TJsonParserOptions): boolean;
var
  tmp: TSynTempBuffer;
begin
  tmp.Init(Json);
  if tmp.len <> 0 then
    try
      JsonToObject(ObjectInstance, tmp.buf, result, TObjectListItemClass, Options);
    finally
      tmp.Done;
    end
  else
    result := false;
end;

function JsonToNewObject(var From: PUtf8Char; var Valid: boolean;
  Options: TJsonParserOptions): TObject;
var
  ctxt: TJsonParserContext;
begin
  ctxt.Init(From, nil, Options, nil, nil);
  result := ctxt.ParseNewObject;
end;

function PropertyFromJson(Prop: PRttiCustomProp; Instance: TObject;
  From: PUtf8Char; var Valid: boolean; Options: TJsonParserOptions): PUtf8Char;
var
  ctxt: TJsonParserContext;
begin
  Valid := false;
  result := nil;
  if (Prop = nil) or
     (Prop^.Value.Kind <> rkClass) or
     (Instance = nil) then
    exit;
  ctxt.Init(From, Prop^.Value, Options, nil, nil);
  if not JsonLoadProp(pointer(Instance), Prop^, ctxt) then
    exit;
  Valid := true;
  result := ctxt.Json;
end;

function UrlDecodeObject(U: PUtf8Char; Upper: PAnsiChar;
  var ObjectInstance; Next: PPUtf8Char; Options: TJsonParserOptions): boolean;
var
  tmp: RawUtf8;
begin
  result := UrlDecodeValue(U, Upper, tmp, Next);
  if result then
    JsonToObject(ObjectInstance, Pointer(tmp), result, nil, Options);
end;

function JsonFileToObject(const JsonFile: TFileName; var ObjectInstance;
  TObjectListItemClass: TClass; Options: TJsonParserOptions): boolean;
var
  tmp: RawUtf8;
begin
  tmp := AnyTextFileToRawUtf8(JsonFile, true);
  if tmp = '' then
    result := false
  else
  begin
    RemoveCommentsFromJson(pointer(tmp));
    JsonToObject(ObjectInstance, pointer(tmp), result, TObjectListItemClass, Options);
  end;
end;

procedure JsonBufferToXML(P: PUtf8Char; const Header, NameSpace: RawUtf8;
  out result: RawUtf8);
var
  i, j, L: integer;
  temp: TTextWriterStackBuffer;
begin
  if P = nil then
    result := Header
  else
    with TTextWriter.CreateOwnedStream(temp) do
    try
      AddNoJsonEscape(pointer(Header), length(Header));
      L := length(NameSpace);
      if L <> 0 then
        AddNoJsonEscape(pointer(NameSpace), L);
      AddJsonToXML(P);
      if L <> 0 then
        for i := 1 to L do
          if NameSpace[i] = '<' then
          begin
            for j := i + 1 to L do
              if NameSpace[j] in [' ', '>'] then
              begin
                Add('<', '/');
                AddStringCopy(NameSpace, i + 1, j - i - 1);
                Add('>');
                break;
              end;
            break;
          end;
      SetText(result);
    finally
      Free;
    end;
end;

function JsonToXML(const Json, Header, NameSpace: RawUtf8): RawUtf8;
var
  tmp: TSynTempBuffer;
begin
  tmp.Init(Json);
  try
    JsonBufferToXML(tmp.buf, Header, NameSpace, result);
  finally
    tmp.Done;
  end;
end;


{ ********************* Abstract Classes with Auto-Create-Fields }

function DoRegisterAutoCreateFields(ObjectInstance: TObject): TRttiJson;
begin // sub procedure for smaller code generation in AutoCreateFields/Create
  result := Rtti.RegisterAutoCreateFieldsClass(PClass(ObjectInstance)^) as TRttiJson;
end;

procedure AutoCreateFields(ObjectInstance: TObject);
var
  rtti: TRttiJson;
  n: integer;
  p: ^PRttiCustomProp;
begin
  // inlined ClassPropertiesGet
  rtti := PPointer(PPAnsiChar(ObjectInstance)^ + vmtAutoTable)^;
  if (rtti = nil) or
     not (rcfAutoCreateFields in rtti.Flags) then
    rtti := DoRegisterAutoCreateFields(ObjectInstance);
  p := pointer(rtti.fAutoCreateClasses);
  if p = nil then
    exit;
  // create all published class fields
  n := PDALen(PAnsiChar(p) - _DALEN)^ + _DAOFF; // length(AutoCreateClasses)
  repeat
    with p^^ do
      PPointer(PAnsiChar(ObjectInstance) + OffsetGet)^ :=
        TRttiJson(Value).fClassNewInstance(Value);
    inc(p);
    dec(n);
  until n = 0;
end;

procedure AutoDestroyFields(ObjectInstance: TObject);
var
  rtti: TRttiJson;
  n: integer;
  p: ^PRttiCustomProp;
  arr: pointer;
  o: TObject;
begin
  rtti := PPointer(PPAnsiChar(ObjectInstance)^ + vmtAutoTable)^;
  // free all published class fields
  p := pointer(rtti.fAutoCreateClasses);
  if p <> nil then
  begin
    n := PDALen(PAnsiChar(p) - _DALEN)^ + _DAOFF;
    repeat
      o := PObject(PAnsiChar(ObjectInstance) + p^^.OffsetGet)^;
      if o <> nil then
        // inlined o.Free
        o.Destroy;
      inc(p);
      dec(n);
    until n = 0;
  end;
  // release all published T*ObjArray fields
  p := pointer(rtti.fAutoCreateObjArrays);
  if p = nil then
    exit;
  n := PDALen(PAnsiChar(p) - _DALEN)^ + _DAOFF;
  repeat
    arr := PPointer(PAnsiChar(ObjectInstance) + p^^.OffsetGet)^;
    if arr <> nil then
      // inlined ObjArrayClear()
      RawObjectsClear(arr, PDALen(PAnsiChar(arr) - _DALEN)^ + _DAOFF);
    inc(p);
    dec(n);
  until n = 0;
end;


{ TPersistentAutoCreateFields }

constructor TPersistentAutoCreateFields.Create;
begin
  AutoCreateFields(self);
end; // no need to call the void inherited TPersistentWithCustomCreate

destructor TPersistentAutoCreateFields.Destroy;
begin
  AutoDestroyFields(self);
  inherited Destroy;
end;


{ TSynAutoCreateFields }

constructor TSynAutoCreateFields.Create;
begin
  AutoCreateFields(self);
end; // no need to call the void inherited TSynPersistent

destructor TSynAutoCreateFields.Destroy;
begin
  AutoDestroyFields(self);
  inherited Destroy;
end;


{ TSynAutoCreateFieldsLocked }

constructor TSynAutoCreateFieldsLocked.Create;
begin
  AutoCreateFields(self);
  inherited Create; // initialize fSafe := NewSynLocker
end;

destructor TSynAutoCreateFieldsLocked.Destroy;
begin
  AutoDestroyFields(self);
  inherited Destroy;
end;


{ TInterfacedObjectAutoCreateFields }

constructor TInterfacedObjectAutoCreateFields.Create;
begin
  AutoCreateFields(self);
end; // no need to call TInterfacedObjectWithCustomCreate.Create

destructor TInterfacedObjectAutoCreateFields.Destroy;
begin
  AutoDestroyFields(self);
  inherited Destroy;
end;


{ TCollectionItemAutoCreateFields }

constructor TCollectionItemAutoCreateFields.Create(Collection: TCollection);
begin
  AutoCreateFields(self);
  inherited Create(Collection);
end;

destructor TCollectionItemAutoCreateFields.Destroy;
begin
  AutoDestroyFields(self);
  inherited Destroy;
end;


{ TSynJsonFileSettings }

function TSynJsonFileSettings.LoadFromJson(var aJson: RawUtf8): boolean;
begin
  result := JsonSettingsToObject(aJson, self);
end;

function TSynJsonFileSettings.LoadFromFile(const aFileName: TFileName): boolean;
begin
  fFileName := aFileName;
  fInitialJsonContent := StringFromFile(aFileName);
  result := LoadFromJson(fInitialJsonContent);
end;

procedure TSynJsonFileSettings.SaveIfNeeded;
var
  saved: RawUtf8;
begin
  if (self = nil) or
     (fFileName = '') then
    exit;
  saved := ObjectToJson(self, SETTINGS_WRITEOPTIONS);
  if saved = fInitialJsonContent then
    exit;
  FileFromString(saved, fFileName);
  fInitialJsonContent := saved;
end;


procedure InitializeUnit;
var
  i: PtrInt;
  c: AnsiChar;
begin
  // branchless JSON escaping - JSON_ESCAPE_NONE=0 if no JSON escape needed
  JSON_ESCAPE[0] := JSON_ESCAPE_ENDINGZERO;   // 1 for #0 end of input
  for i := 1 to 31 do
    JSON_ESCAPE[i] := JSON_ESCAPE_UNICODEHEX; // 2 should be escaped as \u00xx
  JSON_ESCAPE[8]  := ord('b');  // others contain the escaped character
  JSON_ESCAPE[9]  := ord('t');
  JSON_ESCAPE[10] := ord('n');
  JSON_ESCAPE[12] := ord('f');
  JSON_ESCAPE[13] := ord('r');
  JSON_ESCAPE[ord('\')] := ord('\');
  JSON_ESCAPE[ord('"')] := ord('"');
  // branchless JSON parsing
  for c := low(c) to high(c) do
  begin
    if c in [#0, ',', ']', '}', ':'] then
      include(JSON_CHARS[c], jcEndOfJsonFieldOr0);
    if c in [#0, ',', ']', '}'] then
      include(JSON_CHARS[c], jcEndOfJsonFieldNotName);
    if c in [#0, #9, #10, #13, ' ',  ',', '}', ']'] then
      include(JSON_CHARS[c], jcEndOfJsonValueField);
    if c in [#0, '"', '\'] then
      include(JSON_CHARS[c], jcJsonStringMarker);
    if c in ['-', '0'..'9'] then
    begin
      include(JSON_CHARS[c], jcDigitFirstChar);
      JSON_TOKENS[c] := jtFirstDigit;
    end;
    if c in ['-', '+', '0'..'9', '.', 'E', 'e'] then
      include(JSON_CHARS[c], jcDigitFloatChar);
    if c in ['_', '0'..'9', 'a'..'z', 'A'..'Z', '$'] then
      include(JSON_CHARS[c], jcJsonIdentifierFirstChar);
    if c in ['_', 'a'..'z', 'A'..'Z', '$'] then
      // exclude '0'..'9' as already in jcDigitFirstChar
      JSON_TOKENS[c] := jtIdentifierFirstChar;
    if c in ['_', '0'..'9', 'a'..'z', 'A'..'Z', '.', '[', ']'] then
      include(JSON_CHARS[c], jcJsonIdentifier);
  end;
  JSON_TOKENS['{'] := jtObjectStart;
  JSON_TOKENS['}'] := jtObjectStop;
  JSON_TOKENS['['] := jtArrayStart;
  JSON_TOKENS[']'] := jtArrayStop;
  JSON_TOKENS[':'] := jtAssign;
  JSON_TOKENS[','] := jtComma;
  JSON_TOKENS[''''] := jtSingleQuote;
  JSON_TOKENS['"'] := jtDoubleQuote;
  JSON_TOKENS['t'] := jtTrueFirstChar;
  JSON_TOKENS['f'] := jtFalseFirstChar;
  JSON_TOKENS['n'] := jtNullFirstChar;
  JSON_TOKENS['/'] := jtSlash;
  // initialize JSON serialization
  Rtti.GlobalClass := TRttiJson; // will ensure Rtti.Count = 0
  GetDataFromJson := _GetDataFromJson;
end;


initialization
  InitializeUnit;
  DefaultTextWriterSerializer := TTextWriter;
  
end.

