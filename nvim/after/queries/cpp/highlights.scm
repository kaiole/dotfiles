; extends

; Language tokens that upstream captures as values/functions (or leaves uncaptured).
; Keep this token-specific: @constant.builtin also includes stdin, __FILE__, etc.
; Priority 130 also beats clangd's type/operator colors (125-127).
([
  (this)
  (true)
  (false)
  "nullptr"
  "static_assert"
  "operator"
  "alignas"
  "consteval"
  "constinit"
  "export"
  "import"
  "module"
  "decltype"
] @keyword
  (#set! priority 130))

; clangd calls word operators simply "operator", but these are still keywords.
([
  "sizeof"
  "alignof"
  "new"
  "delete"
  "and"
  "or"
  "not"
  "xor"
  "bitand"
  "bitor"
  "compl"
  "and_eq"
  "or_eq"
  "xor_eq"
  "not_eq"
] @keyword.operator
  (#set! priority 130))

; The C++ grammar parses these reserved words as identifiers.
((identifier) @keyword
  (#any-of? @keyword "static_cast" "dynamic_cast" "reinterpret_cast" "const_cast" "typeid" "noexcept")
  (#set! priority 130))

; The inherited @type capture spans the entire type_descriptor in decltype(name).
; Let the operand remain a variable even without clangd.
(decltype
  (identifier) @variable
  (#set! priority 110))
