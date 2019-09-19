////////////////////////////////////////////////////////////////////////////////
// initializer (globals, options, functions, debug)
////////////////////////////////////////////////////////////////////////////////
{
   // add #defines and remove #undefs
   var defined = {};
//   var defined = {"__cplusplus":""};

   var log = []; // debug
   
   // options
   var pos = true; // TODO:
   var json = false;
 
   if ("pos" in options) pos = str2bool(options.pos);
   if ("json" in options) json = str2bool(options.json);

   //
   function str2bool(str) {
      if (typeof str == "boolean") return str;
      if (str.toLowerCase() == "true") return true
      return false;
   }

   //
   function processBlock(block) {
      var procBlk = "";

      block.forEach(function (elem) {
         if ("code" in elem) 
            procBlk += processCode(elem["code"]);
         else if ("if stmt" in elem) 
            procBlk += processIf(elem);
         else
            error("unsupported statement type " + JSON.stringify(elem));
      });
      
      return procBlk;
   }
   
   //
   function processCode(code) {
      for (var i = 0; i < code.length; i++) {
         // macro replacement (code could have affect on expression evaluation)
         Object.keys(defined).forEach(function (macro) {
            // do not replace a redefinition
            var regex = new RegExp("# *(define|undef)[ \t]+" + macro + "\\b");
            var match = regex.exec(code[i]);
            
            if (!match) {
               // object-like macro
               if (typeof defined[macro] == "string") {
                  regex = new RegExp("\\b" + macro + "\\b", "g");
                  code[i] = code[i].replace(regex, defined[macro]);
               }
               // function-like macro
               else
                  code[i] = replaceMacroFunc(macro, code[i]);
            }
         });
         
         //
         // (add #defines to)/(remove #undefs from) defined{}
         //
         
         // #define func()
         //    verified with gcc compiler that there can 
         //    be no whitespace between macro ID and '('
         var match = /# *define[ \t]+(\w+)\(/.exec(code[i]);
         
         if (match) {
            // determine first matching parentheses to get arg list and body
            var open = match[0].length - 1;
            var closeAndArgs = getCloseParenPosAndArgs(code[i], open);
            var body = code[i].slice(closeAndArgs["close"] + 1).trim();

            if (RegExp("\\b" + match[1] + "[ \t]*\\(").exec(body)) 
               error("recursive macro functions not supported " +
               "(or call to previoulsy defined function of the same name)");

            defined[match[1]] = {"args": closeAndArgs["args"], "body": body};

            continue;
         }
         
         // #define
         match = /# *define[ \t]+(\w+)([ \t]+([^\r\n]+))?/.exec(code[i]);
         
         if (match) {
            defined[match[1]] = match[3] ? match[3] : "";
            continue;
         }

         // #undef
         match = /# *undef[ \t]+(\w+)/.exec(code[i]);
         if (match) delete(defined[match[1]]);
      }      
      
      return code.join('\n');
   }
   
   //
   function processIf(if_stmt) {
     switch(if_stmt["if stmt"]) {
         case "ifdef":
            if (if_stmt["name"] in defined)
               return processBlock(if_stmt["afterif"]["if"]);
            else
               return processElses(if_stmt["afterif"]);
         case "ifndef":
            if (if_stmt["name"] in defined)
               return processElses(if_stmt["afterif"]);
            else
               return processBlock(if_stmt["afterif"]["if"]);
         case "if":
            if (processExpr(if_stmt["expr"]))
              return processBlock(if_stmt["afterif"]["if"]);
            else
               return processElses(if_stmt["afterif"]);
         default: error("unsupported if stmt: " + if_stmt["if stmt"]);
      }
   }
   
   // return processBlock() for first elif or else expression that is true
   function processElses(afterif) {
      var procBlk = "";

      for (var i = 0; i < afterif["elifs"].length; i++) {
         var elem = afterif["elifs"][i];

         if (processExpr(elem["expr"])) {
            procBlk = processBlock(elem["block"]);
            break;
         }
      }

      if ((procBlk == "") && ("else" in afterif))
         procBlk = processBlock(afterif["else"]);

      return procBlk;
   }
   
   //
   function processExpr(expr) {
      var regex;
      
      // macro replacement
      //
      // use 0/1 instead of false/true since all remaining IDs (words) will be
      // set to false (0). This assumes true or false will not be used in
      // expressions
      // TODO: true/false in expressions?
      // TODO: function calls in expressions
      Object.keys(defined).forEach(function (macro) {
         // replace defined(macroID) with true (1)
         // TODO: allow more whitespaces around parentheses?
         regex = new RegExp("defined\\([ \t]*" + macro + "[ \t]*\\)", "g");
         expr = expr.replace(regex, 1);
         
         // replace remaining macros
         if (typeof defined[macro] == "string") {
            regex = new RegExp("\\b" + macro + "\\b", "g");
            // if no value, set to true (1)
            var val = defined[macro] == "" ? 1 : defined[macro];
            expr = expr.replace(regex, val);
         }
         else
            expr = replaceMacroFunc(macro, expr);
      });
      
      // set remaining define()s to false (0)
      regex = new RegExp("defined\\([^)]+\\)", "g");
      expr = expr.replace(regex, 0);
      
      // set remaining IDs to false (0)
      regex = new RegExp("[a-zA-Z_][a-zA-Z_0-9]*", "g");
      expr = expr.replace(regex, 0);
      
      try { 
         return eval(expr); 
      }
      catch (err) {
         error(err);
      }
   }

   //
   function replaceMacroFunc(macro, line) {
      // check if line contains macro ID followed by '('
      var regex = new RegExp("\\b" + macro + "[ \t]*\\(");
      var match = regex.exec(line);
      if (!match) return line;

      // check if def is variadic
      var lastArgIndx = defined[macro].args.length - 1;
      var lastArg = defined[macro].args[lastArgIndx];
      var vargMatch = RegExp("([a-zA-Z_][a-zA-Z_0-9]*)?\\.\\.\\.").exec(lastArg);
      // default varg ID
      var vargID_regex = "(##)?" + "\\b__VA_ARGS__\\b";
      // named varg ID
      if (vargMatch && vargMatch[1]) 
         vargID_regex = "(##)?" + "\\b" + vargMatch[1] + "\\b";
      // check if "##" used before vargs ID in body
      var rtc_match = RegExp(vargID_regex).exec(defined[macro]["body"]);
      var rmTrailingComma = (rtc_match && rtc_match[1]) ? true : false;

      // TODO: need better failsafe, but good for IDE debugging dohs ...
      var count = 0;

      // may be more than one func call in expr (line)
      do {
         if (count++ > 100) error("replaceMacroFunc: infinte loop?");
         
         // get macro call args (between open and close parentheses)
         var open = match.index + match[0].length - 1;
         var closeAndArgs = getCloseParenPosAndArgs(line, open);
         var close = closeAndArgs["close"];
         var args = closeAndArgs["args"];

         // check that def and call have the same number of args
         // or defined func is variadic
         if ((args.length != defined[macro].args.length) && !vargMatch) 
            error("macroFuncRep(): number of args mismatch for " + 
                  macro + ": " + JSON.stringify(args) + ": " +
                  JSON.stringify(defined[macro].args));

         // for current match, 
         // replace each macro def arg with corresponding call arg
         var rep = defined[macro]["body"];
         var arg_regex;
         var remainingArgs = [];
                        
         for (var i = 0; i <= lastArgIndx; i++) {
            // TODO: do not have to join() array?
            remainingArgs = args.slice(i);

            // if next to last index AND this is a variadic function with 
            // "##vargID" in the body AND call does not pass vargs,
            // then replace "def_arg, ##vargID" with "call_arg" (no comma)
            if (((i+1) == lastArgIndx) &&
                vargMatch && 
                rmTrailingComma &&
                (remainingArgs.length == 1)) {

               arg_regex = new RegExp("\\b" + defined[macro].args[i] + 
                                      "[ \t]*,[ \t]*" + vargID_regex,
                                      "g");
               rep = rep.replace(arg_regex, args[i]);
               break; // done
            }
            // if last index AND this is a variadic function, 
            // replace varg ID with remaining call arg list
            else if ((i == lastArgIndx) && vargMatch) 
               rep = rep.replace(RegExp(vargID_regex, "g"), remainingArgs);
            // replace macro def arg with corresponding call arg
            else {
               arg_regex = new RegExp("\\b" + defined[macro].args[i] + "\\b", 
                                      "g");
               rep = rep.replace(arg_regex, args[i]);
            }
         }

         // replace macro call with modified macro def
         line = line.slice(0, match.index) + rep + line.slice(close + 1);
         
         match = regex.exec(line);
         
      } while (match);

      return line;
   }
   
   // Arg list may contain nested parentheses (even declarations could have 
   // func ptrs). Could have been handled with regex recursion but javascript 
   // does not support. Better handled by parsing stage, but simple enough to 
   // do here. Only need to find matching close parenthesis for open parenthesis
   // after function ID. Handling in parser would add more info to pass between 
   // parse and process stages and lose the simplicity of parsing file into 
   // just "if_stmt" and "code" types and in cleaning up the code to remove
   // line continuations, carriage returns, multi-line comments, etc.
   function getCloseParenPosAndArgs(line, firstOpen) {
      var open = firstOpen;
      var close = line.indexOf(')', firstOpen);
         
      while (true) {
         open = line.indexOf('(', open + 1);
         // found when no more '(' or next '(' beyond last ')'
         if ((open == -1) || (open > close)) break;
         close = line.indexOf(')', close + 1);
      }
      
      var args = line.slice(firstOpen + 1, close).split(',').map(e => e.trim());

      return {"close": close, "args": args};
   }
}

////////////////////////////////////////////////////////////////////////////////
// grammar
////////////////////////////////////////////////////////////////////////////////

parseTree = ws? block:block ws? {
   var result = {"stmts": block};

   // process after parsing so that macros can be evaluated in order
   if (!json) result = processBlock(block);
   
   if (log.length) {
      if (!json) {
         result = {"stmts": result};
         result["defined"] = defined;
      }
      
      result["debug"] = log;
    }
  
    return result;
}

block = stmts:(if_stmt / code / SL_COMMENT)* { 
   // remove comments (empty strings)
   return stmts.filter(e => e != "");
}

// note there can be a whitespace between the '#' and keyword
if_stmt = ifdefs / _if

ifdefs = '#' _? type:("ifdef" / "ifndef") _ name:ID afterif:afterif {
   return {"if stmt": type, "name": name, "afterif": afterif};   
}

_if = '#' _? "if" _? expr:const_expr afterif:afterif {
   return {"if stmt": "if", "expr": expr, "afterif": afterif};   
}

afterif = ws block:block elifs:get_elifs* 
          _else:('#' _? "else" ws block)? '#' _? "endif" ws? {
          
   var json = {"if": block, "elifs": elifs};
   if (_else) json["else"] = _else[4];
   return json;
}

get_elifs = '#' _? "elif" _ expr:const_expr ws block:block {
   return {"expr": expr, "block": block}; 
}

////////////////////////////////////////////////////////////////////////////////
// TERMINALS
////////////////////////////////////////////////////////////////////////////////

const_expr = get_upto_eol 

get_upto_eol = txt:$(((!(cont / '\n' / '\r') .)+ / cont)+) { 
   // remove whitespace seqs (including line continuation) with single space
   return txt.replace(/\\\s*[\r\n]+/g, ' ').replace(/\s\s*/g, ' ').trim();
}

// include multi-line comments since they can be embedded anywhere within a line
// multiple times, then remove later
code = code:$((ML_COMMENT / (!(SL_COMMENT / if_keywd) .))+) {
   // replace line continuations, carriage returns, 
   // multi-line comments and multiple spaces/tabs before splitting
   var json =  {"code": code.replace(/\\[ \t]*[\r\n]+/g, '')
                            .replace(/\r/g, '')
                            .replace(/\/\*((?!\*\/).)*\*\//sg, '')
                            // TODO: don't change orig whitespace?
                            .replace(/[ \t][ \t]*/g, ' ')
                            .split('\n')}; 
   return json;

}

if_keywd = '#' _? ("if" / "elif" / "else" / "endif")

_ "space/tab(s)" = (' ' / '\t' / cont)+ { return  ' '; }
// line continuation
cont "cont" = '\\' [ \t]* [\r\n]+ [ \t]* { return  ' '; }
ML_COMMENT "MLcomm" = "/*" (!"*/" .)* "*/" { return ''; }
ws = ([ \t\r\n] / ML_COMMENT / SL_COMMENT)+

////////////////////////////////////////////////////////////////////////////////
// XTEXT TERMINALS
////////////////////////////////////////////////////////////////////////////////

ID "ID" = id:$([a-zA-Z_] [a-zA-Z_0-9]*) { return id; }
INT "INT" = $([0-9]+)
SL_COMMENT "SLcomm" = "//" [^\r\n]* { return ''; }
