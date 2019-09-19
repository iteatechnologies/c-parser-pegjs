////////////////////////////////////////////////////////////////////////////////
// initializer (globals, options, functions, debug)
////////////////////////////////////////////////////////////////////////////////
{
   var log = []; // debug
   
   // TODO: options
   var pos = true;
   if ("pos" in options) pos = str2bool(options.pos);

   //
   function str2bool(str) {
      if (typeof str == "boolean") return str;
      if (str.toLowerCase() == "true") return true
      return false;
   }

   // TODO: asterisk after brackets?
   // if array pointer, moves asterisk after brackets
   // adds indices if present
   function getArrayType(type, indices) {
      var str = "";
      
      if (indices) {
         indices.forEach(function (elem) {
            str += '[' + elem + ']';
         });
      }
      else
         str = "[]";
   
      var index = type.indexOf('*');
         
      if (index == -1)
         return type + str;
      else
         // no string splice?
         return type.slice(0,index) + str + type.slice(index);
   }
}

////////////////////////////////////////////////////////////////////////////////
// grammar
////////////////////////////////////////////////////////////////////////////////

parseTree = WS? stmts:statements* { 
   var json = {"statements": stmts};
   if (log.length) json["debug"] = log;
   return json; 
}

statements = preproc / typedef / struct / union / enum / 
             extern / func_call / inline_func / declare 

////////////////////////////////////////////////////////////////////////////////
// preprocessor
////////////////////////////////////////////////////////////////////////////////

preproc =  include / define / undef / pragma / unsupported

include = '#' _? "include" _ includef:includef { 
  return {"type": "preproc include", "filename": includef}; 
}

includef = '"' hfile:hfile '"' WS? { return hfile; }
/ '<' hfile:hfile '>' WS? { return hfile; }

define = '#' _? "define" _ name:ID args:argList? body:get_upto_eol? WS? {
    var json = {"type": "preproc define", "name": name};
    
    if (args && body) {
       json["type"] = "preproc define (func)";
       json["args"] = args;
       json["body"] = body ? body.trim() : body;
    }
    else {
       // not a function
       if (args) 
          json["value"] = '(' + args.join(',') + ')';
       else
          json["value"] = body ? body.trim() : body;
    }
    
    return json;
}

undef = '#' _? "undef" _ name:ID WS? { 
   return {"type": "preproc undef", "name": name};
}

pragma = '#' _? "pragma" dir:get_upto_eol WS? {
   return {"type": "preproc pragma", "directive": dir};
}

unsupported = ("#line" / "#error") get_upto_eol WS? { 
   return error("This preprocessor is not currently supported"); 
}

////////////////////////////////////////////////////////////////////////////////
// typedef
////////////////////////////////////////////////////////////////////////////////

typedef = "typedef" _ type:(td_struct / td_enum / td_union / func_ptr / ID)
          aliases:aliases? EOS { 
          
   var json = {"type": "typedef", "typedef": type};
   if (aliases) json["aliases"] = aliases;
   return json;
}

aliases = _? aliases:get_aliases+ { return aliases; }

// TODO: alias type? (if ID used, needs more WS work)
//get_aliases = alias:ID ',' { return alias.trim(); }

get_aliases = alias:alias ','? { return alias.trim(); }

td_struct = "struct" name:(_ ID)? WS? '{' WS? 
         members:(get_mem / union / define / s_func_ptr)* '}' {
          
   var json = {"type": "struct"};
   
   if (name) json["name"] = name[1];
   json["members"] = members;
   
   return json;
}

struct = struct:td_struct vary:(_? ID)? EOS {
   if (vary) struct["variable"] = vary[1];
   return struct;
}

get_mem = tokens:get_tokens fields:get_fields+ EOS { 
   var json = {"type": tokens["type"]};
   
   if (tokens["mods"].length) json["modifiers"] = tokens["mods"];
   
   // struct members can be broken down further into fields
   // e.g a char int separate 8 bit fields
   // if only one field, combine objects, else create fields object
   if (fields.length == 1) 
      json = Object.assign({}, json, fields[0]);
   else
      json["fields"] = fields;
      
   return json;
}

get_fields= field:field _? ','? WS? { return field; }

field = '*'? id:ID size:('[' $([^\]]+) ']')? width:(_? ':' _? (ID / INT))? {

   var json = {"name":id};
   
   if (size) json["size"] = size[1].trim();
   if (width) json["width"] = width[3];
   
   return json;
}

td_enum = "enum" name:(_ name:ID)? WS? '{' WS? enums:get_enums* '}' {
          
   var json = {"type": "enum"};

   if (name) json["name"] = name[1];
   json["enums"] = enums;
   
   return json;
}

enum = enums:td_enum vary:(_? ID)? EOS { 
   if (vary) enums["variable"] = vary[1];
   return enums; 
}

get_enums = name:ID val:(_? '=' _? expr)? _? ','? WS? { 
   var json = {"name":name};
   if (val) json["value"] = val[3];
   return json;
}

// typedef union, don't check for alias
td_union = "union" name:(_ ID)? WS? '{' WS? members:(get_mem / struct)* '}' {
          
   var json = {"type": "union"};
   
   if (name) json["name"] = name[1];
   json["members"] = members;
   
   return json;
}

union = union:td_union vary:(_? ID)? EOS {
   if (vary) union["variable"] = vary[1];
   return union;
}

func_ptr = tokens:get_tokens? type:(ID _)? '(' _? '*' _? name:ID _? ')' _?
           params:paramList {

   var json = {"type": "function ptr",
               "name": name,
               "params": params};
 
   // get_tokens will not include type since '(' is a delimeter, unless it is a 
   // pointer ('*' not a delim)
   if (type) {
      json["return type"] = type[0];
      // type in tokens is actually a modifer
      if (tokens) tokens["mods"].unshift(tokens["type"])
   }
   else {
      if (!tokens) error("func_ptr: tokens should be present if no type");
      json["return type"] = tokens["type"];
   }
               
   if (tokens && tokens["mods"].length) json["modifiers"] = tokens["mods"];
   
   return json;
}

s_func_ptr = ptr:func_ptr EOS { return ptr; }

////////////////////////////////////////////////////////////////////////////////
// 
////////////////////////////////////////////////////////////////////////////////

// TODO: assert?
func_call = name:ID args:argList WS? {
   return {"type": "macro assert", "name": name, "args": args};
}

inline_func = tokens:get_tokens meth:method WS? body:block WS? {
   meth["type"] = "inline func";
   meth["return type"] = tokens["type"];
   if (tokens["mods"].length) meth["modifiers"] = tokens["mods"];
   meth["body"] = body;
   
   return meth;
}

// TODO: breakdown further?
block = '{' block:$(block / [^{}])* '}' { return block; }

declare = tokens:get_tokens name:(method / array / ID) EOS {
   var json =  {"type:": "declaration"};
   
   // method or array
   if (typeof name == "object") {
      json["declaration"] = name;
   
      if (name["type"] == "array") 
         name["type"] = getArrayType(tokens["type"]);
      else
         name["return type"] = tokens["type"];
   }
   // ID
   else
      json["declaration"] = {"type": tokens["type"], "name": name};
   
   if (tokens["mods"].length) json["modifiers"] = tokens["mods"];
   
   return json;
}

extern = "extern" _ ('"C"' / "'C'") WS? '{' WS? stmts:statements* '}' WS? {
   return {"type": "extern", "statements": stmts};
}

////////////////////////////////////////////////////////////////////////////////
// expression
////////////////////////////////////////////////////////////////////////////////

method = name:ID params:paramList {
   return {"type": "method", "name": name, "params": params};
}

// name optional if used as parameter
array = name:ID? indices:get_index+ { 
   return {"type": "array", "name": name, "indices": indices}; 
}

get_index = _? '[' index:$([^\]])* ']' { return index; }

// TODO: is this enough?
expr = expr:$((atom _? ('+' / "<<") _? atom) / atom / '(' _? expr _? ')')

atom = ID / INT / STRING

////////////////////////////////////////////////////////////////////////////////
// parms/args
////////////////////////////////////////////////////////////////////////////////

paramList = WS? '(' params:(get_params / get_params_noname)* ')' { 
   return params; 
}

get_params = WS? tokens:get_tokens? 
             name:(func_ptr / array / ID / vargs) WS? ','? WS? {

   var json = {};
   
   // funct_ptr or Array
   if (typeof name == "object") {
      if (name["type"] == "array") {
         if (tokens) {
            json["type"] = getArrayType(tokens["type"], name["indices"]);
            if (name["name"]) json["name"] = name["name"];
         }
         else
            json["type"] = getArrayType(name["name"], name["indices"]);
      }
      else 
         json = name;
   }
   // ID or vargs
   else {
      if (tokens)
         json = {"type": tokens["type"], "name": name};
      else
         // param with type only
         json = {"type": name}
   }
   
   if (tokens && tokens["mods"].length) json["modifiers"] = tokens["mods"];

   return json; 
}

get_params_noname = WS? tokens:get_tokens WS? ','? WS? {

   var json = {"type": tokens["type"]};
   if (tokens["mods"].length) json["modifiers"] = tokens["mods"];
   return json; 
}

// gets tokens (IDs) not including token before delimeters
get_tokens = tokens:get_id+ ptr:('*' / _)* WS? {
   var type = tokens.pop();
   if (ptr) type += ptr.join('');
   return {"type": type, "mods": tokens};
}

get_id = id:ID _? !delim { return id; }

argList = WS? '(' args:get_args* ')' { return args; }

get_args = WS? arg:$arg+ WS? ','? WS? { return arg.trim(); }

////////////////////////////////////////////////////////////////////////////////
// TERMINALS
////////////////////////////////////////////////////////////////////////////////

// TODO: this will not work for function calls as args
arg "arg" = arg:$([^(),])+ 
get_upto_eol = _? eol:$(escape / [^\r\n\\]+)+ { return eol; }
alias "alias" = $([^,;]+)
hfile "hfile" = $([a-zA-Z_] [a-zA-Z_0-9./-]*)
delim = WS? [;()[:,]
vargs "vargs" = "..." { return "varadic args"; }

_ "space/tab(s)" = [ \t]+ { return ""; }
EOS = (_? ';')+ WS?

////////////////////////////////////////////////////////////////////////////////
// XTEXT TERMINALS
////////////////////////////////////////////////////////////////////////////////

WS "WS" = ([ \t\r\n]+)  { return ""; }
ID "ID" = id:$([a-zA-Z_] [a-zA-Z_0-9]*) { return id; }
INT "INT"  = $([0-9]+)

STRING = "'" str:$(charValue1*) "'" { return str; } 
/        '"' str:$(charValue2*) '"' { return str; } 

charValue1 "char1" = hexEscape / octEscape / charEscape / [^\r\n']
charValue2 "char2" = hexEscape / octEscape / charEscape / [^\r\n"]
hexEscape = '\\' ("x" / "X") [0-9A-Za-z] [0-9A-Za-z]
octEscape = '\\' [0-7] [0-7] [0-7]
charEscape = '\\' ("a" / "b" / "f" / "n" / "r" / "t" / "v" / '\\' / "'" / '"')
escape = hexEscape / octEscape / charEscape
