"use strict";
{
  var f;
  function f() {}
} // SyntaxError in Node, yours compiles
{
  function f() {}
  var f;
} // SyntaxError in Node, yours compiles
