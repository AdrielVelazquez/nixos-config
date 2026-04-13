local M = {}

local did_setup = false

local textobject_queries = {
  bash = [=[
(function_definition) @function.outer

(function_definition
 body: (compound_statement
 .
 "{"
 _+ @function.inner
 "}"))

(case_statement) @conditional.outer

(if_statement
 (_) @conditional.inner) @conditional.outer

(for_statement
 (_) @loop.inner) @loop.outer

(while_statement
 (_) @loop.inner) @loop.outer

(comment) @comment.outer

(regex) @regex.inner

((word) @number.inner
 (#lua-match? @number.inner "^[0-9]+$"))

(variable_assignment) @assignment.outer

(variable_assignment
 name: (_) @assignment.inner @assignment.lhs)

(variable_assignment
 value: (_) @assignment.inner @assignment.rhs)

(command
 argument: (word) @parameter.inner)
]=],
  dart = [=[
; class
((annotation)? @class.outer
 .
 (class_definition
 body: (class_body) @class.inner) @class.outer)

(mixin_declaration
 (class_body) @class.inner) @class.outer

(enum_declaration
 body: (enum_body) @class.inner) @class.outer

(extension_declaration
 body: (extension_body) @class.inner) @class.outer

; function/method
((annotation)? @function.outer
 .
 [
 (method_signature)
 (function_signature)
 ] @function.outer
 .
 (function_body) @function.outer)

(function_body
 (block
 .
 "{"
 _+ @function.inner
 "}"))

(type_alias
 (function_type)? @function.inner) @function.outer

; parameter
[
 (formal_parameter)
 (normal_parameter_type)
 (type_parameter)
] @parameter.inner

("," @parameter.outer
 .
 [
 (formal_parameter)
 (normal_parameter_type)
 (type_parameter)
 ] @parameter.outer)

([
 (formal_parameter)
 (normal_parameter_type)
 (type_parameter)
] @parameter.outer
 .
 "," @parameter.outer)

; TODO: (_)* not supported yet -> for now this works correctly only with simple arguments
(arguments
 .
 (_) @parameter.inner @parameter.outer
 .
 ","? @parameter.outer)

(arguments
 "," @parameter.outer
 .
 (_) @parameter.inner @parameter.outer)

; call
((identifier) @call.outer
 .
 (selector
 (argument_part) @call.outer))

((identifier)
 .
 (selector
 (argument_part
 (arguments
 .
 "("
 _+ @call.inner
 ")"))))

; block
(block) @block.outer

; conditional
(if_statement
 [
 condition: (_)
 consequence: (_)
 alternative: (_)?
 ] @conditional.inner) @conditional.outer

(switch_statement
 body: (switch_block) @conditional.inner) @conditional.outer

(conditional_expression
 [
 consequence: (_)
 alternative: (_)
 ] @conditional.inner) @conditional.outer

; loop
(for_statement
 body: (block) @loop.inner) @loop.outer

(while_statement
 body: (block) @loop.inner) @loop.outer

(do_statement
 body: (block) @loop.inner) @loop.outer

; comment
[
 (comment)
 (documentation_comment)
] @comment.outer

; statement
[
 (break_statement)
 (do_statement)
 (expression_statement)
 (for_statement)
 (if_statement)
 (return_statement)
 (switch_statement)
 (while_statement)
 (assert_statement)
 (yield_statement)
 (yield_each_statement)
 (continue_statement)
 (try_statement)
] @statement.outer
]=],
  go = [=[
; inner function textobject
(function_declaration
 body: (block
 .
 "{"
 _+ @function.inner
 "}"))

; inner function literals
(func_literal
 body: (block
 .
 "{"
 _+ @function.inner
 "}"))

; method as inner function textobject
(method_declaration
 body: (block
 .
 "{"
 _+ @function.inner
 "}"))

; outer function textobject
(function_declaration) @function.outer

; outer function literals
(func_literal
 (_)?) @function.outer

; method as outer function textobject
(method_declaration
 body: (block)?) @function.outer

; struct and interface declaration as class textobject?
(type_declaration
 (type_spec
 (type_identifier)
 (struct_type
 (field_declaration_list
 (_)?) @class.inner))) @class.outer

(type_declaration
 (type_spec
 (type_identifier)
 (interface_type) @class.inner)) @class.outer

; struct literals as class textobject
(composite_literal
 (type_identifier)?
 (struct_type
 (_))?
 (literal_value
 (_)) @class.inner) @class.outer

; conditionals
(if_statement
 alternative: (_
 (_) @conditional.inner)?) @conditional.outer

(if_statement
 consequence: (block)? @conditional.inner)

(if_statement
 condition: (_) @conditional.inner)

; loops
(for_statement
 body: (block)? @loop.inner) @loop.outer

; blocks
(_
 (block) @block.inner) @block.outer

; statements
(block
 (_) @statement.outer)

; comments
(comment) @comment.outer

; calls
(call_expression) @call.outer

(call_expression
 arguments: (argument_list
 .
 "("
 _+ @call.inner
 ")"))

; parameters
(parameter_list
 "," @parameter.outer
 .
 (parameter_declaration) @parameter.inner @parameter.outer)

(parameter_list
 .
 (parameter_declaration) @parameter.inner @parameter.outer
 .
 ","? @parameter.outer)

(parameter_declaration
 name: (identifier)
 type: (_)) @parameter.inner

(parameter_declaration
 name: (identifier)
 type: (_)) @parameter.inner

(parameter_list
 "," @parameter.outer
 .
 (variadic_parameter_declaration) @parameter.inner @parameter.outer)

; arguments
(argument_list
 "," @parameter.outer
 .
 (_) @parameter.inner @parameter.outer)

(argument_list
 .
 (_) @parameter.inner @parameter.outer
 .
 ","? @parameter.outer)

; assignments
(short_var_declaration
 left: (_) @assignment.lhs
 right: (_) @assignment.rhs @assignment.inner) @assignment.outer

(assignment_statement
 left: (_) @assignment.lhs
 right: (_) @assignment.rhs @assignment.inner) @assignment.outer

(var_spec
 name: (_) @assignment.lhs
 value: (_) @assignment.rhs @assignment.inner) @assignment.outer

(var_spec
 name: (_) @assignment.inner
 type: (_)) @assignment.outer

(const_spec
 name: (_) @assignment.lhs
 value: (_) @assignment.rhs @assignment.inner) @assignment.outer

(const_spec
 name: (_) @assignment.inner
 type: (_)) @assignment.outer
]=],
  hcl = [=[
(attribute
 (identifier) @assignment.lhs
 (expression) @assignment.inner @assignment.rhs) @assignment.outer

(attribute
 (identifier) @assignment.inner)

(block
 (body)? @block.inner) @block.outer

(block
 (body
 (_) @statement.outer))

(function_call
 (function_arguments) @call.inner) @call.outer

(comment) @comment.outer

(conditional
 (expression) @conditional.inner) @conditional.outer

(for_cond
 (expression) @conditional.inner) @conditional.outer

(for_expr
 (for_object_expr
 (for_intro) @loop.inner
 (expression) @loop.inner
 (expression) @loop.inner
 (for_cond)? @loop.inner)) @loop.outer

(for_expr
 (for_object_expr
 (for_intro) @loop.inner))

(for_expr
 (for_object_expr
 (expression) @loop.inner))

(for_expr
 (for_tuple_expr
 (for_intro) @loop.inner
 (expression) @loop.inner
 (for_cond)? @loop.inner)) @loop.outer

(for_expr
 (for_tuple_expr
 (for_intro) @loop.inner))

(for_expr
 (for_tuple_expr
 (expression) @loop.inner))

(numeric_lit) @number.inner

(function_arguments
 "," @parameter.outer
 .
 (expression) @parameter.inner @parameter.outer)

(function_arguments
 .
 (expression) @parameter.inner @parameter.outer
 .
 ","? @parameter.outer)
]=],
  html = [=[
(element) @function.outer

(element
 (start_tag)
 .
 (_) @function.inner
 .
 (end_tag))

(attribute_value) @attribute.inner

(attribute) @attribute.outer

(element
 (start_tag)
 _+ @function.inner
 (end_tag))

(script_element) @function.outer

(script_element
 (start_tag)
 .
 (_) @function.inner
 .
 (end_tag))

(style_element) @function.outer

(style_element
 (start_tag)
 .
 (_) @function.inner
 .
 (end_tag))

((element
 (start_tag
 (tag_name) @_tag)) @class.outer
 (#match? @_tag "^(html|section|h[0-9]|header|title|head|body)$"))

((element
 (start_tag
 (tag_name) @_tag)
 .
 (_) @class.inner
 .
 (end_tag))
 (#match? @_tag "^(html|section|h[0-9]|header|title|head|body)$"))

((element
 (start_tag
 (tag_name) @_tag)
 _+ @class.inner
 (end_tag))
 (#match? @_tag "^(html|section|h[0-9]|header|title|head|body)$"))

(comment) @comment.outer
]=],
  lua = [=[
; block
(_
 (block) @block.inner) @block.outer

; call
(function_call) @call.outer

(function_call
 (arguments) @call.inner
 (#match? @call.inner "^[^\\(]"))

(function_call
 arguments: (arguments
 .
 "("
 _+ @call.inner
 ")"))

; comment
(comment
 (comment_content) @comment.inner) @comment.outer

; conditional
(if_statement
 alternative: (_
 (_) @conditional.inner)?) @conditional.outer

(if_statement
 consequence: (block)? @conditional.inner)

(if_statement
 condition: (_) @conditional.inner)

; function
[
 (function_declaration)
 (function_definition)
] @function.outer

(function_declaration
 body: (_) @function.inner)

(function_definition
 body: (_) @function.inner)

; return
(return_statement
 (_)? @return.inner) @return.outer

; loop
[
 (while_statement)
 (for_statement)
 (repeat_statement)
] @loop.outer

(while_statement
 body: (_) @loop.inner)

(for_statement
 body: (_) @loop.inner)

(repeat_statement
 body: (_) @loop.inner)

; parameter
(arguments
 .
 (_) @parameter.inner @parameter.outer
 .
 ","? @parameter.outer)

(parameters
 .
 (_) @parameter.inner @parameter.outer
 .
 ","? @parameter.outer)

(table_constructor
 (field) @parameter.inner @parameter.outer
 ","? @parameter.outer)

(arguments
 "," @parameter.outer
 .
 (_) @parameter.inner @parameter.outer)

(parameters
 "," @parameter.outer
 .
 (_) @parameter.inner @parameter.outer)

; number
(number) @number.inner

(assignment_statement
 (variable_list) @assignment.lhs
 (expression_list) @assignment.inner @assignment.rhs) @assignment.outer

(assignment_statement
 (variable_list) @assignment.inner)

; statement
(statement) @statement.outer

(return_statement) @statement.outer
]=],
  nix = [=[
; named function
(binding
 (function_expression)) @function.outer

; anonymous function
(function_expression
 (_) ; argument
 (_) @function.inner) @function.outer

(function_expression
 (formals
 (formal) @parameter.inner))

(function_expression
 (_) @parameter.outer
 (_))

(comment) @comment.outer

(if_expression
 (_) @conditional.inner) @conditional.outer

[
 (integer_expression)
 (float_expression)
] @number.inner
]=],
  python = [=[
(decorated_definition
 (function_definition)) @function.outer

(function_definition
 body: (block)? @function.inner) @function.outer

(decorated_definition
 (class_definition)) @class.outer

(class_definition
 body: (block)? @class.inner) @class.outer

(while_statement
 body: (block)? @loop.inner) @loop.outer

(for_statement
 body: (block)? @loop.inner) @loop.outer

(if_statement
 alternative: (_
 (_) @conditional.inner)?) @conditional.outer

(if_statement
 consequence: (block)? @conditional.inner)

(if_statement
 condition: (_) @conditional.inner)

(_
 (block) @block.inner) @block.outer

; leave space after comment marker if there is one
((comment) @comment.inner @comment.outer
 (#offset! @comment.inner 0 2 0 0)
 (#lua-match? @comment.outer "# .*"))

; else remove everything accept comment marker
((comment) @comment.inner @comment.outer
 (#offset! @comment.inner 0 1 0 0))

(block
 (_) @statement.outer)

(module
 (_) @statement.outer)

(call) @call.outer

(call
 arguments: (argument_list
 .
 "("
 _+ @call.inner
 ")"))

(return_statement
 (_)? @return.inner) @return.outer

; Parameters
(parameters
 "," @parameter.outer
 .
 [
 (identifier)
 (tuple)
 (typed_parameter)
 (default_parameter)
 (typed_default_parameter)
 (dictionary_splat_pattern)
 (list_splat_pattern)
 ] @parameter.inner @parameter.outer)

(parameters
 .
 [
 (identifier)
 (tuple)
 (typed_parameter)
 (default_parameter)
 (typed_default_parameter)
 (dictionary_splat_pattern)
 (list_splat_pattern)
 ] @parameter.inner @parameter.outer
 .
 ","? @parameter.outer)

(lambda_parameters
 "," @parameter.outer
 .
 [
 (identifier)
 (tuple)
 (typed_parameter)
 (default_parameter)
 (typed_default_parameter)
 (dictionary_splat_pattern)
 (list_splat_pattern)
 ] @parameter.inner @parameter.outer)

(lambda_parameters
 .
 [
 (identifier)
 (tuple)
 (typed_parameter)
 (default_parameter)
 (typed_default_parameter)
 (dictionary_splat_pattern)
 (list_splat_pattern)
 ] @parameter.inner @parameter.outer
 .
 ","? @parameter.outer)

(tuple
 "," @parameter.outer
 .
 (_) @parameter.inner @parameter.outer)

(tuple
 "("
 .
 (_) @parameter.inner @parameter.outer
 .
 ","? @parameter.outer)

(list
 "," @parameter.outer
 .
 (_) @parameter.inner @parameter.outer)

(list
 .
 (_) @parameter.inner @parameter.outer
 .
 ","? @parameter.outer)

(set
 "," @parameter.outer
 .
 (_) @parameter.inner @parameter.outer)

(set
 .
 (_) @parameter.inner @parameter.outer
 .
 ","? @parameter.outer)

(dictionary
 .
 (pair) @parameter.inner @parameter.outer
 .
 ","? @parameter.outer)

(dictionary
 "," @parameter.outer
 .
 (pair) @parameter.inner @parameter.outer)

(argument_list
 .
 (_) @parameter.inner @parameter.outer
 .
 ","? @parameter.outer)

(argument_list
 "," @parameter.outer
 .
 (_) @parameter.inner @parameter.outer)

(subscript
 "["
 .
 (_) @parameter.inner @parameter.outer
 .
 ","? @parameter.outer)

(subscript
 "," @parameter.outer
 .
 (_) @parameter.inner @parameter.outer)

(import_statement
 .
 (_) @parameter.inner @parameter.outer
 .
 ","? @parameter.outer)

(import_statement
 "," @parameter.outer
 .
 (_) @parameter.inner @parameter.outer)

(import_from_statement
 "," @parameter.outer
 .
 (_) @parameter.inner @parameter.outer)

(import_from_statement
 "import"
 .
 (_) @parameter.inner @parameter.outer
 .
 ","? @parameter.outer)

[
 (integer)
 (float)
] @number.inner

(assignment
 left: (_) @assignment.lhs
 right: (_) @assignment.inner @assignment.rhs) @assignment.outer

(assignment
 left: (_) @assignment.inner)

(augmented_assignment
 left: (_) @assignment.lhs
 right: (_) @assignment.inner @assignment.rhs) @assignment.outer

(augmented_assignment
 left: (_) @assignment.inner)
]=],
  rust = [=[
; functions
(function_signature_item) @function.outer

(function_item) @function.outer

(function_item
 body: (block
 .
 "{"
 _+ @function.inner
 "}"))

; quantifies as class(es)
(struct_item) @class.outer

(struct_item
 body: (field_declaration_list
 .
 "{"
 _+ @class.inner
 "}"))

(enum_item) @class.outer

(enum_item
 body: (enum_variant_list
 .
 "{"
 _+ @class.inner
 "}"))

(union_item) @class.outer

(union_item
 body: (field_declaration_list
 .
 "{"
 _+ @class.inner
 "}"))

(trait_item) @class.outer

(trait_item
 body: (declaration_list
 .
 "{"
 _+ @class.inner
 "}"))

(impl_item) @class.outer

(impl_item
 body: (declaration_list
 .
 "{"
 _+ @class.inner
 "}"))

(mod_item) @class.outer

(mod_item
 body: (declaration_list
 .
 "{"
 _+ @class.inner
 "}"))

; conditionals
(if_expression
 alternative: (_
 (_) @conditional.inner)?) @conditional.outer

(if_expression
 alternative: (else_clause
 (block) @conditional.inner))

(if_expression
 condition: (_) @conditional.inner)

(if_expression
 consequence: (block) @conditional.inner)

(match_arm
 (_)) @conditional.inner

(match_expression) @conditional.outer

; loops
(loop_expression
 body: (block
 .
 "{"
 _+ @loop.inner
 "}")) @loop.outer

(while_expression
 body: (block
 .
 "{"
 _+ @loop.inner
 "}")) @loop.outer

(for_expression
 body: (block
 .
 "{"
 _+ @loop.inner
 "}")) @loop.outer

; blocks
(block
 (_)* @block.inner) @block.outer

(unsafe_block
 (_)* @block.inner) @block.outer

; calls
(macro_invocation) @call.outer

(macro_invocation
 (token_tree
 .
 "("
 _+ @call.inner
 ")"))

(call_expression) @call.outer

(call_expression
 arguments: (arguments
 .
 "("
 _+ @call.inner
 ")"))

; returns
(return_expression
 (_)? @return.inner) @return.outer

; statements
(block
 (_) @statement.outer)

; comments
(line_comment) @comment.outer

(block_comment) @comment.outer

; parameter
(parameters
 "," @parameter.outer
 .
 [
 (self_parameter)
 (parameter)
 (type_identifier)
 ] @parameter.inner @parameter.outer)

(parameters
 .
 [
 (self_parameter)
 (parameter)
 (type_identifier)
 ] @parameter.inner @parameter.outer
 .
 ","? @parameter.outer)

; last element, with trailing comma
(parameters
 [
 (self_parameter)
 (parameter)
 (type_identifier)
 ] @parameter.outer
 .
 "," @parameter.outer .)

(type_parameters
 "," @parameter.outer
 .
 (_) @parameter.inner @parameter.outer)

(type_parameters
 .
 (_) @parameter.inner @parameter.outer
 .
 ","? @parameter.outer)

; last element, with trailing comma
(type_parameters
 (_) @parameter.outer
 .
 "," @parameter.outer .)

(tuple_pattern
 "," @parameter.outer
 .
 (identifier) @parameter.inner @parameter.outer)

(tuple_pattern
 .
 (identifier) @parameter.inner @parameter.outer
 .
 ","? @parameter.outer)

; last element, with trailing comma
(tuple_pattern
 (identifier) @parameter.outer
 .
 "," @parameter.outer .)

(tuple_struct_pattern
 "," @parameter.outer
 .
 (identifier) @parameter.inner @parameter.outer)

(tuple_struct_pattern
 .
 (identifier) @parameter.inner @parameter.outer
 .
 ","? @parameter.outer)

; last element, with trailing comma
(tuple_struct_pattern
 (identifier) @parameter.outer
 .
 "," @parameter.outer .)

(tuple_expression
 "," @parameter.outer
 .
 (_) @parameter.inner @parameter.outer)

(tuple_expression
 .
 (_) @parameter.inner @parameter.outer
 .
 ","? @parameter.outer)

; last element, with trailing comma
(tuple_expression
 (_) @parameter.outer
 .
 "," @parameter.outer .)

(tuple_type
 "," @parameter.outer
 .
 (_) @parameter.inner @parameter.outer)

(tuple_type
 .
 (_) @parameter.inner @parameter.outer
 .
 ","? @parameter.outer)

; last element, with trailing comma
(tuple_type
 (_) @parameter.outer
 .
 "," @parameter.outer .)

(enum_variant
 body: (ordered_field_declaration_list
 "," @parameter.outer
 .
 (_) @parameter.inner @parameter.outer))

(enum_variant
 body: (ordered_field_declaration_list
 .
 (_) @parameter.inner @parameter.outer
 .
 ","? @parameter.outer))

; last element, with trailing comma
(enum_variant
 body: (ordered_field_declaration_list
 (_) @parameter.outer
 .
 "," @parameter.outer .))

(struct_item
 body: (field_declaration_list
 "," @parameter.outer
 .
 (_) @parameter.inner @parameter.outer))

(struct_item
 body: (field_declaration_list
 .
 (_) @parameter.inner @parameter.outer
 .
 ","? @parameter.outer))

; last element, with trailing comma
(struct_item
 body: (field_declaration_list
 (_) @parameter.outer
 .
 "," @parameter.outer .))

(struct_expression
 body: (field_initializer_list
 "," @parameter.outer
 .
 (_) @parameter.inner @parameter.outer))

(struct_expression
 body: (field_initializer_list
 .
 (_) @parameter.inner @parameter.outer
 .
 ","? @parameter.outer))

; last element, with trailing comma
(struct_expression
 body: (field_initializer_list
 (_) @parameter.outer
 .
 "," @parameter.outer .))

(closure_parameters
 "," @parameter.outer
 .
 (_) @parameter.inner @parameter.outer)

(closure_parameters
 .
 (_) @parameter.inner @parameter.outer
 .
 ","? @parameter.outer)

; last element, with trailing comma
(closure_parameters
 (_) @parameter.outer
 .
 "," @parameter.outer .)

(arguments
 "," @parameter.outer
 .
 (_) @parameter.inner @parameter.outer)

(arguments
 .
 (_) @parameter.inner @parameter.outer
 .
 ","? @parameter.outer)

; last element, with trailing comma
(arguments
 (_) @parameter.outer
 .
 "," @parameter.outer .)

(type_arguments
 "," @parameter.outer
 .
 (_) @parameter.inner @parameter.outer)

(type_arguments
 .
 (_) @parameter.inner @parameter.outer
 .
 ","? @parameter.outer)

; last element, with trailing comma
(type_arguments
 (_) @parameter.outer
 .
 "," @parameter.outer .)

(token_tree
 "," @parameter.outer
 .
 (_) @parameter.inner @parameter.outer)

(token_tree
 .
 (_) @parameter.inner @parameter.outer
 .
 ","? @parameter.outer)

; last element, with trailing comma
(token_tree
 (_) @parameter.outer
 .
 "," @parameter.outer .)

(scoped_use_list
 list: (use_list
 "," @parameter.outer
 .
 (_) @parameter.inner @parameter.outer))

(scoped_use_list
 list: (use_list
 .
 (_) @parameter.inner @parameter.outer
 .
 ","? @parameter.outer))

; last element, with trailing comma
(scoped_use_list
 list: (use_list
 (_) @parameter.outer
 .
 "," @parameter.outer .))

[
 (integer_literal)
 (float_literal)
] @number.inner

(let_declaration
 pattern: (_) @assignment.lhs
 value: (_) @assignment.inner @assignment.rhs) @assignment.outer

(let_declaration
 pattern: (_) @assignment.inner)

(assignment_expression
 left: (_) @assignment.lhs
 right: (_) @assignment.inner @assignment.rhs) @assignment.outer

(assignment_expression
 left: (_) @assignment.inner)
]=],
  vim = [=[
(comment) @comment.outer

(function_definition
 (body) @function.inner) @function.outer

(parameters
 (identifier) @parameter.inner)

(parameters
 "," @parameter.outer
 .
 (identifier) @parameter.outer)

(parameters
 .
 (identifier) @parameter.outer
 .
 "," @parameter.outer)

(if_statement
 (body) @conditional.inner) @conditional.outer

(for_loop
 (body) @loop.inner) @loop.outer

(while_loop
 (body) @loop.inner) @loop.outer

(call_expression) @call.outer

(return_statement
 (_)? @return.inner) @return.outer

(_
 (body) @block.inner) @block.outer

(body
 (_) @statement.outer)

((syntax_statement
 (pattern) @regex.inner @regex.outer)
 (#offset! @regex.outer 0 -1 0 1))

[
 (integer_literal)
 (float_literal)
] @number.inner

(let_statement
 (_) @assignment.lhs
 (_) @assignment.rhs @assignment.inner) @assignment.outer

(let_statement
 (_) @assignment.inner)
]=],
  yaml = [=[
; assignment, statement
(block_mapping_pair
 key: (_) @assignment.lhs
 value: (_) @assignment.rhs) @assignment.outer @statement.outer

(block_mapping_pair
 key: (_) @assignment.inner)

(block_mapping_pair
 value: (_) @assignment.inner)

; comment
; leave space after comment marker if there is one
((comment) @comment.inner @comment.outer
 (#offset! @comment.inner 0 2 0 0)
 (#lua-match? @comment.outer "# .*"))

; else remove everything accept comment marker
((comment) @comment.inner @comment.outer
 (#offset! @comment.inner 0 1 0 0))

; number
[
 (integer_scalar)
 (float_scalar)
] @number.inner
]=],
  zig = [=[
; "Classes"
(variable_declaration
 (struct_declaration)) @class.outer

(variable_declaration
 (struct_declaration
 "struct"
 "{"
 _+ @class.inner
 "}"))

; functions
(function_declaration) @function.outer

(function_declaration
 body: (block
 .
 "{"
 _+ @function.inner
 "}"))

; loops
(for_statement) @loop.outer

(for_statement
 body: (_) @loop.inner)

(while_statement) @loop.outer

(while_statement
 body: (_) @loop.inner)

; blocks
(block) @block.outer

(block
 "{"
 _+ @block.inner
 "}")

; statements
(statement) @statement.outer

; parameters
(parameters
 "," @parameter.outer
 .
 (parameter) @parameter.inner @parameter.outer)

(parameters
 .
 (parameter) @parameter.inner @parameter.outer
 .
 ","? @parameter.outer)

; arguments
(call_expression
 function: (_)
 arguments: (arguments
 "("
 "," @parameter.outer
 .
 (_) @parameter.inner @parameter.outer
 ")"))

(call_expression
 function: (_)
 arguments: (arguments
 "("
 .
 (_) @parameter.inner @parameter.outer
 .
 ","? @parameter.outer
 ")"))

; comments
(comment) @comment.outer

; conditionals
(if_statement) @conditional.outer

(if_statement
 condition: (_) @conditional.inner)

(if_statement
 body: (_) @conditional.inner)

(switch_expression) @conditional.outer

(switch_expression
 "("
 (_) @conditional.inner
 ")")

(switch_expression
 "{"
 _+ @conditional.inner
 "}")

(while_statement
 condition: (_) @conditional.inner)

; calls
(call_expression) @call.outer

(call_expression
 arguments: (arguments
 "("
 _+ @call.inner
 ")"))
]=],
}

local function compare_pos(row_a, col_a, row_b, col_b)
  if row_a ~= row_b then
    return row_a < row_b and -1 or 1
  end

  if col_a ~= col_b then
    return col_a < col_b and -1 or 1
  end

  return 0
end

local function range_contains(range, row, col)
  local start_cmp = compare_pos(range[1], range[2], row, col)
  local end_cmp = compare_pos(row, col, range[3], range[4])
  return start_cmp <= 0 and end_cmp < 0
end

local function range_size(range)
  return (range[3] - range[1]) * 1000000 + (range[4] - range[2])
end

local function range_key(lang, range)
  return string.format('%s:%d:%d:%d:%d', lang, range[1], range[2], range[3], range[4])
end

local function normalize_capture(capture)
  return (capture:gsub('^@', ''))
end

local function capture_range(nodes, bufnr, metadata)
  local combined

  for _, node in ipairs(nodes) do
    local current_range = vim.treesitter.get_range(node, bufnr, metadata)
    local current = { current_range[1], current_range[2], current_range[4], current_range[5] }

    if not combined then
      combined = current
    else
      if compare_pos(current[1], current[2], combined[1], combined[2]) < 0 then
        combined[1], combined[2] = current[1], current[2]
      end

      if compare_pos(current[3], current[4], combined[3], combined[4]) > 0 then
        combined[3], combined[4] = current[3], current[4]
      end
    end
  end

  return combined
end

local function get_capture_matches(bufnr, capture, query_group)
  local capture_name = normalize_capture(capture)
  local parser = vim.treesitter.get_parser(bufnr, nil, { error = false })
  if not parser then
    return {}
  end

  parser:parse()

  local matches = {}
  local seen = {}

  parser:for_each_tree(function(tree, ltree)
    local query = vim.treesitter.query.get(ltree:lang(), query_group)
    if not query then
      return
    end

    local root = tree:root()
    local start_row, _, end_row, _ = root:range()

    for _, match, metadata in query:iter_matches(root, bufnr, start_row, end_row + 1) do
      for id, nodes in pairs(match) do
        if query.captures[id] == capture_name then
          local range = capture_range(nodes, bufnr, metadata and metadata[id] or nil)
          if range then
            local key = range_key(ltree:lang(), range)
            if not seen[key] then
              seen[key] = true
              table.insert(matches, {
                lang = ltree:lang(),
                range = range,
              })
            end
          end
        end
      end
    end
  end)

  return matches
end

local function current_cursor(win)
  local row, col = unpack(vim.api.nvim_win_get_cursor(win or 0))
  return row - 1, col
end

local function get_vim_range(range, bufnr)
  local start_row, start_col, end_row, end_col = unpack(range)
  start_row = start_row + 1
  start_col = start_col + 1
  end_row = end_row + 1

  if end_col == 0 then
    end_row = end_row - 1
    local line = vim.api.nvim_buf_get_lines(bufnr, end_row - 1, end_row, false)[1] or ''
    end_col = math.max(#line, 1)
  end

  return start_row, start_col, end_row, end_col
end

local function select_range(bufnr, range, selection_mode)
  local start_row, start_col, end_row, end_col = get_vim_range(range, bufnr)
  local visual_mode = selection_mode or 'v'

  if visual_mode == 'charwise' then
    visual_mode = 'v'
  elseif visual_mode == 'linewise' then
    visual_mode = 'V'
  elseif visual_mode == 'blockwise' then
    visual_mode = vim.api.nvim_replace_termcodes('<C-v>', true, true, true)
  end

  if vim.api.nvim_get_mode().mode ~= visual_mode then
    vim.api.nvim_cmd({ cmd = 'normal', bang = true, args = { visual_mode } }, {})
  end

  vim.api.nvim_win_set_cursor(0, { start_row, start_col - 1 })
  vim.cmd.normal { 'o', bang = true }
  vim.api.nvim_win_set_cursor(0, { end_row, end_col - 1 })
end

local function goto_range(bufnr, range, use_start)
  local start_row, start_col, end_row, end_col = get_vim_range(range, bufnr)
  local target = use_start and { start_row, start_col - 1 } or { end_row, end_col - 1 }

  if vim.api.nvim_get_mode().mode == 'no' then
    vim.cmd.normal { 'v', bang = true }
  end

  vim.api.nvim_win_set_cursor(0, target)
end

local function pick_textobject(bufnr, capture)
  local row, col = current_cursor()
  local containing = {}
  local lookahead = {}

  for _, match in ipairs(get_capture_matches(bufnr, capture, 'textobjects')) do
    if range_contains(match.range, row, col) then
      table.insert(containing, match)
    elseif compare_pos(match.range[1], match.range[2], row, col) > 0 then
      table.insert(lookahead, match)
    end
  end

  table.sort(containing, function(left, right)
    local left_size = range_size(left.range)
    local right_size = range_size(right.range)

    if left_size ~= right_size then
      return left_size < right_size
    end

    return compare_pos(left.range[1], left.range[2], right.range[1], right.range[2]) < 0
  end)

  if containing[1] then
    return containing[1].range
  end

  table.sort(lookahead, function(left, right)
    local cmp = compare_pos(left.range[1], left.range[2], right.range[1], right.range[2])
    if cmp ~= 0 then
      return cmp < 0
    end

    return range_size(left.range) < range_size(right.range)
  end)

  return lookahead[1] and lookahead[1].range or nil
end

local function move_to_capture(bufnr, capture, forward, use_start)
  local row, col = current_cursor()
  local best_match
  local best_row
  local best_col

  for _, match in ipairs(get_capture_matches(bufnr, capture, 'textobjects')) do
    local target_row = use_start and match.range[1] or match.range[3]
    local target_col = use_start and match.range[2] or match.range[4]
    local cmp = compare_pos(target_row, target_col, row, col)

    if forward and cmp > 0 then
      if not best_match or compare_pos(target_row, target_col, best_row, best_col) < 0 then
        best_match = match
        best_row = target_row
        best_col = target_col
      end
    elseif not forward and cmp < 0 then
      if not best_match or compare_pos(target_row, target_col, best_row, best_col) > 0 then
        best_match = match
        best_row = target_row
        best_col = target_col
      end
    end
  end

  if best_match then
    goto_range(bufnr, best_match.range, use_start)
  end
end

function M.setup()
  if did_setup then
    return
  end

  did_setup = true

  for lang, query in pairs(textobject_queries) do
    vim.treesitter.query.set(lang, 'textobjects', query)
  end

  vim.treesitter.language.register('bash', { 'sh', 'zsh' })
  vim.treesitter.language.register('hcl', { 'terraform', 'terraform-vars' })
  vim.treesitter.language.register('json', { 'jsonc' })
end

function M.select(capture, opts)
  local bufnr = vim.api.nvim_get_current_buf()
  local range = pick_textobject(bufnr, capture)

  if range then
    select_range(bufnr, range, opts and opts.selection_mode or 'v')
  end
end

function M.goto_next_start(capture)
  move_to_capture(vim.api.nvim_get_current_buf(), capture, true, true)
end

function M.goto_next_end(capture)
  move_to_capture(vim.api.nvim_get_current_buf(), capture, true, false)
end

function M.goto_previous_start(capture)
  move_to_capture(vim.api.nvim_get_current_buf(), capture, false, true)
end

function M.goto_previous_end(capture)
  move_to_capture(vim.api.nvim_get_current_buf(), capture, false, false)
end

return M
