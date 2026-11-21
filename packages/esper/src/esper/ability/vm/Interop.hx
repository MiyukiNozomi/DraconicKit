package esper.ability.vm;

import esper.ability.vm.Value.JSValue;

// Self is what the caller passed as the receiver.
// Aka `array.unshift()`  self would be `array`.
typedef EsperFunction = (self:JSValue, arguments:Array<JSValue>) -> Void;
