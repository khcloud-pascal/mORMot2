## TDocVariant custom variant typeTDocVariant

## 自定义变体类型

By AB4327-GANDI, 2014-02-25. [Permalink](https://blog.synopse.info/?post/2014/02/25/TDocVariant-custom-variant-type) [Open Source](https://blog.synopse.info/?category/Open-Source-Projects) › [mORMot Framework](https://blog.synopse.info/?category/Open-Source-Projects/mORMot-Framework)

作者：AB4327-GANDI，2014 年 2 月 25 日。永久链接 开源 › mORMot 框架

- [AJAX  （阿贾克斯）](https://blog.synopse.info/?tag/AJAX)
- [blog  （博客）](https://blog.synopse.info/?tag/blog)
- [Delphi ](https://blog.synopse.info/?tag/Delphi)
- [Documentation  （文档）](https://blog.synopse.info/?tag/Documentation)
- [DomainDriven  （领域驱动）](https://blog.synopse.info/?tag/DomainDriven)
- [DTO  （数据传输组织）](https://blog.synopse.info/?tag/DTO)
- [dynamic array  （动态数组）](https://blog.synopse.info/?tag/dynamic%20array)
- [IDE  （集成开发环境）](https://blog.synopse.info/?tag/IDE)
- [JSON](https://blog.synopse.info/?tag/JSON)
- [LateBinding  （后期绑定）](https://blog.synopse.info/?tag/LateBinding)
- [mORMot](https://blog.synopse.info/?tag/mORMot)
- [object  （对象）](https://blog.synopse.info/?tag/object)
- [ORM](https://blog.synopse.info/?tag/ORM)
- [Parsing  （解析）](https://blog.synopse.info/?tag/Parsing)
- [performance  （表现）](https://blog.synopse.info/?tag/performance)
- [RAD](https://blog.synopse.info/?tag/RAD)
- [record  （记录类型）](https://blog.synopse.info/?tag/record)
- [sharding  （分片）](https://blog.synopse.info/?tag/sharding)
- [SOA  （面向服务架构）](https://blog.synopse.info/?tag/SOA)
- [string  （字符串）](https://blog.synopse.info/?tag/string)
- [TDocVariant ](https://blog.synopse.info/?tag/TDocVariant)
- [TDynArray ](https://blog.synopse.info/?tag/TDynArray)

With revision 1.18 of the framework, we just introduced two new custom types of `variant`s:

在框架的 1.18 版本中，我们刚刚引入了两种新的自定义类型的变体：

- `TDocVariant` kind of `variant`;
- TDocVariant 变体类型；
- `TBSONVariant` kind of `variant`.
- TBSONVariant 变体类型。

The second custom type (which handles *MongoDB*-specific extensions - like `ObjectID` or other specific types like dates or binary) will be presented later, when dealing with *MongoDB* support in *mORMot*, together with the BSON kind of content. BSON / *MongoDB* support is implemented in the `SynMongoDB.pas` unit.

稍后在处理 mORMot 中的 MongoDB 支持以及 BSON 类型的内容时，将介绍第二种自定义类型（处理特定于 MongoDB 的扩展 - 例如 ObjectID 或其他特定类型，例如日期或二进制）。 BSON / MongoDB 支持在 SynMongoDB.pas 单元中实现。

We will now focus on `TDocVariant` itself, which is a generic container of JSON-like objects or arrays.

我们现在将重点关注 TDocVariant 本身，它是类似 JSON 的对象或数组的通用容器。  
This custom variant type is implemented in `SynCommons.pas` unit, so is ready to be used everywhere in your code, even without any link to the *mORMot* ORM kernel, or *MongoDB*.

此自定义变体类型在 SynCommons.pas 单元中实现，因此可以在代码中的任何位置使用，即使没有任何到 mORMot ORM 内核或 MongoDB 的链接。

![](http://www.kumc.edu/Images/information%20resources/document-management-software.jpg)

#### TDocVariant documentsTDocVariant 文档

`TDocVariant` implements a custom variant type which can be used to store any JSON/BSON document-based content, i.e. either:

TDocVariant 实现了自定义变体类型，可用于存储任何基于 JSON/BSON 文档的内容，即：

- Name/value pairs, for object-oriented documents;
- 名称/值对，用于面向对象的文档；
- An array of values (including nested documents), for array-oriented documents;
- 值数组（包括嵌套文档），用于面向数组的文档；
- Any combination of the two, by nesting `TDocVariant` instances.
- 通过嵌套 TDocVariant 实例，两者的任意组合。

Here are the main features of this custom variant type:

以下是此自定义变体类型的主要功能：

- DOM approach of any *object* or *array* documents;
- 任何对象或数组文档的 DOM 方法；
- Perfect storage for dynamic value-objects content, with a *schema-less* approach (as you may be used to in scripting languages like Python or JavaScript);
- 使用无模式方法完美存储动态值对象内容（正如您可能习惯使用 Python 或 JavaScript 等脚本语言一样）；
- Allow nested documents, with no depth limitation but the available memory;
- 允许嵌套文档，没有深度限制，但有可用内存；
- Assignment can be either *per-value* (default, safest but slower when containing a lot of nested data), or *per-reference* (immediate reference-counted assignment);
- 赋值可以是每个值（默认，最安全，但包含大量嵌套数据时速度较慢），也可以是每个引用（立即引用计数赋值）；
- Very fast JSON serialization / un-serialization with support of *MongoDB*-like extended syntax;
- 非常快的 JSON 序列化/反序列化，支持类似 MongoDB 的扩展语法；
- Access to properties in code, via late-binding (including almost no speed penalty due to our VCL hack as [already detailed](https://blog.synopse.info/post/2011/07/01/Faster-variant-late-binding));
- 通过后期绑定访问代码中的属性（如前所述，由于我们的 VCL 黑客攻击，几乎没有速度损失）；
- Direct access to the internal variant *names* and *values* arrays from code, by trans-typing into a `TDocVariantData record`;
- 通过转入 TDocVariantData 记录，从代码中直接访问内部变体名称和值数组；
- Instance life-time is managed by the compiler (like any other `variant` type), without the need to use `interfaces` or explicit `try..finally` blocks;
- 实例生命周期由编译器管理（与任何其他变体类型一样），无需使用接口或显式 try..finally 块；
- Optimized to use as little memory and CPU resource as possible (in contrast to most other libraries, it does not allocate one `class` instance per node, but rely on pre-allocated arrays);
- 优化为使用尽可能少的内存和 CPU 资源（与大多数其他库相比，它不会为每个节点分配一个类实例，而是依赖于预先分配的数组）；
- Opened to extension of any content storage - for instance, it will perfectly integrate with BSON serialization and custom *MongoDB* types (*ObjectID, RegEx*...), to be used in conjunction with *MongoDB* servers;
- 开放任何内容存储的扩展 - 例如，它将与 BSON 序列化和自定义 MongoDB 类型（ObjectID、RegEx...）完美集成，与 MongoDB 服务器结合使用；
- Perfectly integrated with our [Dynamic array wrapper](https://blog.synopse.info/post/2011/03/12/TDynArray-and-Record-compare/load/save-using-fast-RTTI) and its JSON serialization as with the [`record` serialization](https://blog.synopse.info/post/2013/12/10/JSON-record-serialization);
- 与我们的动态数组包装器及其 JSON 序列化（如记录序列化）完美集成；
- Designed to work with our *mORMot* ORM: any `TSQLRecord` instance containing such `variant` custom types as published properties will be recognized by the ORM core, and work as expected with any database back-end (storing the content as JSON in a TEXT column);
- 设计用于与我们的 mORMot ORM 配合使用：任何包含此类变体自定义类型作为已发布属性的 TSQLRecord 实例都将被 ORM 核心识别，并按预期与任何数据库后端配合使用（将内容作为 JSON 存储在 TEXT 列中）；
- Designed to work with our *mORMot* SOA: any [`interface`-based service](https://blog.synopse.info/post/2012/03/07/Interface-based-services) is able to consume or publish such kind of content, as `variant` kind of parameters;
- 设计用于与我们的 mORMot SOA 配合使用：任何基于接口的服务都能够使用或发布此类内容，作为参数的变体；
- Fully integrated with the Delphi IDE: any `variant` instance will be displayed as JSON in the IDE debugger, making it very convenient to work with.
- 与 Delphi IDE 完全集成：任何变体实例都将在 IDE 调试器中显示为 JSON，使其使用起来非常方便。

To create instances of such `variant`, you can use some easy-to-remember functions:

要创建此类变体的实例，您可以使用一些易于记住的函数：

- `_Obj() _ObjFast()` global functions to create a `variant` *object* document;
- _Obj() _ObjFast() 用于创建变体对象文档的全局函数；
- `_Arr() _ArrFast()` global functions to create a `variant` *array* document;
- _Arr() _ArrFast() 用于创建变体数组文档的全局函数；
- `_Json() _JsonFast() _JsonFmt() _JsonFastFmt()` global functions to create any `variant` *object* or *array* document from JSON, supplied either with standard or *MongoDB*-extended syntax.
- _Json() _JsonFast() _JsonFmt() _JsonFastFmt() 全局函数，用于从 JSON 创建任何变体对象或数组文档，提供标准或 MongoDB 扩展语法。

### Variant object documents

### 变体对象文档

With `_Obj()`, an *object* `variant` instance will be initialized with data supplied two by two, as *Name,Value* pairs, e.g.

使用 _Obj()，将使用两个两个提供的数据（作为名称、值对，例如）来初始化对象变体实例。

```pascal
var V1,V2: variant;
 ...
 V1 := _Obj(['name','John','year',1972],[dvoValueCopiedByReference]);
 V2 := V1;             // creates a reference to the V1 instance
 V2.name := 'James';   // modifies V2.name, but also V1.name
 writeln(V1.name,' and ',V2.name);
 // will write 'James and James'
```

Then you can convert those objects into JSON, by two means:

然后您可以通过两种方式将这些对象转换为 JSON：

- Using the `VariantSaveJson()` function, which return directly one UTF-8 content;

- 使用VariantSaveJson()函数，直接返回一份UTF-8内容；

- Or by trans-typing the `variant` instance into a string (this will be slower, but is possible).
  
  或者通过将变体实例转换为字符串（这会更慢，但也是可能的）。
  
  ```pascal
  writeln(VariantSaveJson(V1)); / explicit conversion into RawUTF8
  writeln(V1);                  *// implicit conversion from variant into string
  // both commands will write '{"name":"john","year":1982}'
  writeln(VariantSaveJson(V2)); // explicit conversion into RawUTF8
  writeln(V2);                  // implicit conversion from variant into string
  // both commands will write '{"name":"john","doc":{"one":1,"two":2.5}}'
  ```
  
  As a consequence, the Delphi IDE debugger is able to display such variant values as their JSON representation.
  
  因此，Delphi IDE 调试器能够将此类变量值显示为其 JSON 表示形式。  
  That is, `V1` will be displayed as `'"name":"john","year":1982'` in the IDE debugger *Watch List* window, or in the *Evaluate/Modify* (F7) expression tool.
  
  也就是说，V1 将在 IDE 调试器监视列表窗口或评估/修改 (F7) 表达式工具中显示为 '"name":"john","year":1982'。  
  This is pretty convenient, and much more user friendly than any class-based solution (which requires the installation of a specific design-time package in the IDE).
  
  这非常方便，并且比任何基于类的解决方案（需要在 IDE 中安装特定的设计时包）更加用户友好。

You can access to the object properties via late-binding, with any depth of nesting objects, in your code:

您可以在代码中通过后期绑定以及任意深度的嵌套对象来访问对象属性：

```pascal
 writeln('name=',V1.name,' year=',V1.year);
 // will write 'name=John year=1972'
 writeln('name=',V2.name,' doc.one=',V2.doc.one,' doc.two=',doc.two);
 // will write 'name=John doc.one=1 doc.two=2.5
 V1.name := 'Mark';       // overwrite a property value
 writeln(V1.name);        // will write 'Mark'
 V1.age := 12;            // add a property to the object
 writeln(V1.age);         // will write '12'
```

Note that the property names will be evaluated at runtime only, not at compile time.

请注意，属性名称将仅在运行时评估，而不是在编译时评估。  
For instance, if you write `V1.nome` instead of `V1.name`, there will be no error at compilation, but an `EDocVariant` exception will be raised at execution (unless you set the `dvoReturnNullForUnknownProperty` option to `_Obj/_Arr/_Json/_JsonFmt` which will return a `null` variant for such undefined properties).

例如，如果您编写 V1.nome 而不是 V1.name，则编译时不会出现错误，但执行时会引发 EDocVariant 异常（除非您将 dvoReturnNullForUnknownProperty 选项设置为 _Obj/_Arr/_Json/_JsonFmt ，这将返回此类未定义属性的空变体）。

In addition to the property names, some pseudo-methods are available for such *object* `variant` instances:

除了属性名称之外，一些伪方法还可用于此类对象变体实例：

```pascal
writeln(V1._Count); // will write 3 i.e. the number of name/value pairs in the object document
writeln(V1._Kind); // will write 1 i.e. ord(sdkObject)
for i := 0 to V2._Count-1 do
  writeln(V2.Name(i),'=',V2.Value(i));
// will write in the console:
// name=John
// doc={"one":1,"two":2.5}
// age=12
if V1.Exists('year') then
  writeln(V1.year);
```

 You may also trans-type your `variant` instance into a `TDocVariantData record`, and access directly to its internals.

您还可以将变体实例转换为 TDocVariantData 记录，并直接访问其内部。  
For instance:

例如：

```pascal
TDocVariantData(V1).AddValue('comment','Nice guy');
 with TDocVariantData(V1) do // direct transtyping
   if Kind=sdkObject then // direct access to the TDocVariantDataKind field
     for i := 0 to Count-1 do // direct access to the Count: integer field
       writeln(Names[i],'=',Values[i]); // direct access to the internal storage arrays
```

By definition, trans-typing via a `TDocVariantData record` is slightly faster than using late-binding.

根据定义，通过 TDocVariantData 记录进行反式键入比使用后期绑定稍快。  
But you must ensure that the `variant` instance is really a `TDocVariant` kind of data before transtyping e.g. by calling `DocVariantType.IsOfType(aVariant)`.

但在转写之前，您必须确保变体实例确实是 TDocVariant 类型的数据，例如通过调用 DocVariantType.IsOfType(aVariant)。

### Variant array documents

### 变体数组文档

With `_Arr()`, an *array* `variant` instance will be initialized with data supplied as a list of *Value1,Value2,...*, e.g.

使用 _Arr()，将使用以 Value1、Value2、... 列表形式提供的数据来初始化数组变体实例，例如

```pascal
var
   V1,V2: variant; // stored as any variant
 ...
 V1 := _Arr(['John','Mark','Luke']);
 V2 := _Obj(['name','John','array',_Arr(['one','two',2.5])]); // as nested array
```

Then you can convert those objects into JSON, by two means:

然后您可以通过两种方式将这些对象转换为 JSON：

- Using the `VariantSaveJson()` function, which return directly one UTF-8 content;

- 使用VariantSaveJson()函数，直接返回一份UTF-8内容；

- Or by trans-typing the `variant` instance into a string (this will be slower, but is possible).
  
  或者通过将变体实例转换为字符串（这会更慢，但也是可能的）。
  
  ```pascal
  writeln(VariantSaveJson(V1));
  writeln(V1); // implicit conversion from variant into string
  // both commands will write '["John","Mark","Luke"]'
  writeln(VariantSaveJson(V2));
  writeln(V2); // implicit conversion from variant into string
  // both commands will write '{"name":"john","array":["one","two",2.5]}'
  ```
  
  

As a with any *object* document, the Delphi IDE debugger is able to display such *array* `variant` values as their JSON representation.

与任何对象文档一样，Delphi IDE 调试器能够将此类数组变体值显示为其 JSON 表示形式。

Late-binding is also available, with a special set of pseudo-methods:

后期绑定也可用，具有一组特殊的伪方法：

```pascal
writeln(V1._Count); // will write 3 i.e. the number of items in the array document
writeln(V1._Kind);   // will write 2 i.e. ord(sdkArray)*
for i := 0 to V1._Count-1 do
  writeln(V1.Value(i),':',V2._(i));
// will write in the console:
// John John
// Mark Mark
// Luke Luke
if V1.Exists('John') then
   writeln('John found in array');
```

Of course, trans-typing into a `TDocVariantData record` is possible, and will be slightly faster than using late-binding.

当然，转输入 TDocVariantData 记录是可能的，并且比使用后期绑定稍快一些。

### Create variant object or array documents from JSON

### 从 JSON 创建变量对象或数组文档

With `_Json()` or `_JsonFmt()`, either a *document* or *array* `variant` instance will be initialized with data supplied as JSON, e.g.

使用 _Json() 或 _JsonFmt()，文档或数组变体实例将使用 JSON 提供的数据进行初始化，例如

```pascal
var
  V1,V2,V3,V4: variant;  // stored as any variant
 ...
V1 := _Json('{"name":"john","year":1982}');   // strict JSON syntax
V2 := _Json('{name:"john",year:1982}');       // with MongoDB extended syntax for names
V3 := _Json('{"name":?,"year":?}',[],['john',1982]);
V4 := _JsonFmt('{%:?,%:?}',['name','year'],['john',1982]);
writeln(VariantSaveJSON(V1));
writeln(VariantSaveJSON(V2));
writeln(VariantSaveJSON(V3));
// all commands will write '{"name":"john","year":1982}'
```

*

Of course, you can nest objects or arrays as parameters to the `_JsonFmt()` function.

当然，您可以将对象或数组作为参数嵌套到 _JsonFmt() 函数中。

The supplied JSON can be either in strict JSON syntax, or with the *MongoDB* extended syntax, i.e. with unquoted property names.

提供的 JSON 可以采用严格的 JSON 语法，也可以采用 MongoDB 扩展语法，即使用不带引号的属性名称。  
It could be pretty convenient and also less error-prone when typing in the Delphi code to forget about quotes around the property names of your JSON.

在输入 Delphi 代码时忘记 JSON 属性名称周围的引号可能非常方便，而且也不易出错。

Note that *TDocVariant* implements an open interface for adding any custom extensions to JSON: for instance, if the `SynMongoDB.pas` unit is defined in your application, you will be able to create any MongoDB specific types in your JSON, like `ObjectID()`, `new Date()` or even `/regex/option`.

请注意，TDocVariant 实现了一个开放接口，用于向 JSON 添加任何自定义扩展：例如，如果在您的应用程序中定义了 SynMongoDB.pas 单元，您将能够在 JSON 中创建任何 MongoDB 特定类型，例如 ObjectID()、new Date() 甚至 /regex/option。

As a with any *object* or *array* document, the Delphi IDE debugger is able to display such `variant` values as their JSON representation.

与任何对象或数组文档一样，Delphi IDE 调试器能够将此类变量值显示为其 JSON 表示形式。

### Per-value or per-reference

### 每个值或每个引用

By default, the `variant` instance created by `_Obj() _Arr() _Json() _JsonFmt()` will use a *copy-by-value* pattern.

默认情况下，由 _Obj() _Arr() _Json() _JsonFmt() 创建的变体实例将使用按值复制模式。  
It means that when an instance is affected to another variable, a new `variant` document will be created, and all internal values will be copied. Just like a `record` type.

这意味着当一个实例受到另一个变量影响时，将创建一个新的变体文档，并复制所有内部值。就像记录类型一样。

This will imply that if you modify any item of the copied variable, it won't change the original variable:

这意味着如果您修改复制变量的任何项目，它不会更改原始变量：

```pascal
var 
  V1,V2: variant;
 ...
V1 := _Obj(['name','John','year',1972]);
V2 := V1;                             // create a new variant, and copy all values
V2.name := 'James';                   // modifies V2.name, but not V1.name
writeln(V1.name,' and ',V2.name);
// will write 'John and James'
```



As a result, your code will be perfectly safe to work with, since `V1` and `V2` will be uncoupled.

因此，您的代码将非常安全地使用，因为 V1 和 V2 将被解耦。

But one drawback is that passing such a value may be pretty slow, for instance, when you nest objects:

但一个缺点是传递这样的值可能会非常慢，例如，当您嵌套对象时：

```pascal
var 
  V1,V2: variant;
 ...
V1 := _Obj(['name','John','year',1972]);
V2 := _Arr(['John','Mark','Luke']);
V1.names := V2;      // here the whole V2 array will be re-allocated into V1.names
```

Such a behavior could be pretty time and resource consuming, in case of a huge document.

如果文档很大，这种行为可能会非常消耗时间和资源。

All `_Obj() _Arr() _Json() _JsonFmt()` functions have an optional `TDocVariantOptions` parameter, which allows to change the behavior of the created `TDocVariant` instance, especially setting `dvoValueCopiedByReference`.

所有 _Obj() _Arr() _Json() _JsonFmt() 函数都有一个可选的 TDocVariantOptions 参数，该参数允许更改创建的 TDocVariant 实例的行为，特别是设置 dvoValueCopiedByReference。

This particular option will set the *copy-by-reference* pattern:

此特定选项将设置引用复制模式：

```pascal
var
  V1,V2: variant;
 ...
V1 := _Obj(['name','John','year',1972],[dvoValueCopiedByReference]);
V2 := V1;                                      // creates a reference to the V1 instance
V2.name := 'James';                            // modifies V2.name, but also V1.name
writeln(V1.name,' and ',V2.name);
// will write 'James and James'
```



You may think this behavior is somewhat weird for a `variant` type. But if you forget about *per-value* objects and consider those `TDocVariant` types as a Delphi `class` instance (which is a *per-reference* type), without the need of having a fixed schema nor handling manually the memory, it will probably start to make sense.

您可能认为这种行为对于变体类型来说有点奇怪。但是，如果您忘记每个值对象并将这些 TDocVariant 类型视为 Delphi 类实例（这是每个引用类型），而不需要固定模式也不需要手动处理内存，那么它可能会开始有意义。

Note that a set of global functions have been defined, which allows direct creation of documents with *per-reference* instance lifetime, named `_ObjFast() _ArrFast() _JsonFast() _JsonFmtFast()`.

请注意，已定义一组全局函数，允许直接创建具有每个引用实例生存期的文档，名为 _ObjFast() _ArrFast() _JsonFast() _JsonFmtFast()。  
Those are just wrappers around the corresponding `_Obj() _Arr() _Json() _JsonFmt()` functions, with the following `JSON_OPTIONS[true]` constant passed as options parameter:

这些只是相应 _Obj() _Arr() _Json() _JsonFmt() 函数的包装，并使用以下 JSON_OPTIONS[true] 常量作为选项参数传递：

```pascal
const
 */// some convenient TDocVariant options*
 *// - JSON_OPTIONS[false] is _Json() and _JsonFmt() functions default*
 *// - JSON_OPTIONS[true] are used by _JsonFast() and _JsonFastFmt() functions*
 JSON_OPTIONS: **array**[Boolean] **of** TDocVariantOptions = (
 [dvoReturnNullForUnknownProperty],
 [dvoReturnNullForUnknownProperty,dvoValueCopiedByReference]);
```

When working with complex documents, e.g. with BSON / *MongoDB* documents, almost all content will be created in "fast" *per-reference* mode.

处理复杂文档时，例如对于 BSON / MongoDB 文档，几乎所有内容都将以“快速”每引用模式创建。

### Advanced TDocVariant process

### 高级 TDocVariant 流程

### Object or array document creation options

### 对象或数组文档创建选项

As stated above, a `TDocVariantOptions` parameter enables to define the behavior of a `TDocVariant` custom type for a given instance.

如上所述，TDocVariantOptions 参数能够定义给定实例的 TDocVariant 自定义类型的行为。  
Please refer to the documentation of this set of options to find out the available settings. Some are related to the memory model, other to case-sensitivity of the property names, other to the behavior expected in case of non-existing property, and so on...

请参阅这组选项的文档以了解可用的设置。有些与内存模型有关，有些与属性名称的区分大小写有关，有些与不存在属性的情况下预期的行为有关，等等......

Note that this setting is *local* to the given `variant` instance.

请注意，此设置是给定变体实例的本地设置。

In fact, `TDocVariant` does not force you to stick to one memory model nor a set of global options, but you can use the best pattern depending on your exact process.

事实上，TDocVariant 并不强迫您坚持一个内存模型或一组全局选项，但您可以根据您的具体过程使用最佳模式。  
You can even *mix* the options - i.e. including some objects as properties in an object created with other options - but in this case, the initial options of the nested object will remain. So you should better use this feature with caution.

您甚至可以混合选项 - 即包括一些对象作为使用其他选项创建的对象中的属性 - 但在这种情况下，嵌套对象的初始选项将保留。所以您最好谨慎使用此功能。

You can use the `_Unique()` global function to force a variant instance to have an unique set of options, and all nested documents to become *by-value*, or `_UniqueFast()` for all nested documents to become *by-reference*.

您可以使用 _Unique() 全局函数强制变体实例具有一组唯一的选项，并且所有嵌套文档都变为按值，或者使用 _UniqueFast() 使所有嵌套文档变为按引用。

```pascal
// assuming V1='{"name":"James","year":1972}' created by-reference*
 _Unique(V1);                    // change options of V1 to be by-value
 V2 := V1;                       // creates a full copy of the V1 instance
 V2.name := 'John';              // modifies V2.name, but not V1.name
 writeln(V1.name);               // write 'James'
 writeln(V2.name);               // write 'John'
 V1 := _Arr(['root',V2]);        // created as by-value by default, as V2 was
 writeln(V1._Count);             // write 2
 _UniqueFast(V1);                // change options of V1 to be by-reference
 V2 := V1;
 V1._(1).name := 'Jim';
 writeln(V1);
 writeln(V2);
 // both commands will write '["root",{"name":"Jim","year":1972}]'
```



The easiest is to stick to one set of options in your code, i.e.:

最简单的方法是坚持代码中的一组选项，即：

- Either using the `_*()` global functions if your business code does send some `TDocVariant` instances to any other part of your logic, for further storage: in this case, the *by-value* pattern does make sense;
- 如果您的业务代码确实将一些 TDocVariant 实例发送到逻辑的任何其他部分，则使用 _*() 全局函数以进行进一步存储：在这种情况下，按值模式确实有意义；
- Or using the `_*Fast()` global functions if the `TDocVariant` instances are local to a small part of your code, e.g. used as schema-less *Data Transfer Objects* (*DTO*).
- 或者，如果 TDocVariant 实例位于代码的一小部分（例如，用作无模式数据传输对象 (DTO)。

In all cases, be aware that, like any `class` type, the `const`, `var` and `out` specifiers of method parameters does not behave to the `TDocVariant` value, but to its reference.

在所有情况下，请注意，与任何类类型一样，方法参数的 const、var 和 out 说明符并不针对 TDocVariant 值，而是针对其引用。

### Integration with other mORMot units

### 与其他 mORMot 单元集成

In fact, whenever a *schema-less* storage structure is needed, you may use a `TDocVariant` instance instead of `class` or `record` strong-typed types:

事实上，每当需要无模式存储结构时，您都可以使用 TDocVariant 实例来代替类或记录强类型：

- Client-Server ORM will support `TDocVariant` in any of the `TSQLRecord variant` published properties;
- 客户端-服务器 ORM 将在任何 TSQLRecord 变体发布属性中支持 TDocVariant；
- Interface-based services will support `TDocVariant` as `variant` parameters of any method, which make them as perfect *DTO*;
- 基于接口的服务将支持TDocVariant作为任何方法的变量参数，这使得它们成为完美的DTO；
- Since JSON support is implemented with any `TDocVariant` value from the ground up, it makes a perfect fit for working with AJAX clients, in a script-like approach;
- 由于 JSON 支持是从头开始使用任何 TDocVariant 值实现的，因此它非常适合以类似脚本的方式与 AJAX 客户端一起使用；
- If you use our `SynMongoDB.pas` unit to access a *MongoDB* server, `TDocVariant` will be the native storage to create or access BSON arrays or objects documents;
- 如果您使用我们的 SynMongoDB.pas 单元访问 MongoDB 服务器，TDocVariant 将是创建或访问 BSON 数组或对象文档的本机存储；
- Cross-cutting features (like logging or `record` / *dynamic array* enhancements) will also benefit from this `TDocVariant` custom type.
- 横切功能（如日志记录或记录/动态数组增强）也将从这种 TDocVariant 自定义类型中受益。

We are pretty convinced that when you will start playing with `TDocVariant`, you won't be able to live without it any more.

我们非常确信，当您开始使用 TDocVariant 时，您将无法再没有它。  
It introduces the full power of late-binding and schema-less patterns to your application, which can be pretty useful for prototyping or in Agile development.

它向您的应用程序引入了后期绑定和无模式模式的全部功能，这对于原型设计或敏捷开发非常有用。  
You do not need to use scripting engines like Python or JavaScript to have this feature, if you need it.

如果需要，您无需使用 Python 或 JavaScript 等脚本引擎即可拥有此功能。

Feedback and comments are [welcome in our forum, as usual](http://synopse.info/forum/viewtopic.php?id=1631)!

像往常一样，欢迎在我们的论坛中提供反馈和评论！
