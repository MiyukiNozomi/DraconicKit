#!/usr/bin/env node
"use strict";

import { Buffer } from "buffer";
import { loadConfiguration } from "./methods/configuration.js";
import { compileSvelte } from "./methods/svelte-compiler.js";

const HANDLERS = {
  loadConfig: loadConfiguration,
  compileSvelte: compileSvelte,
};

let buffer = Buffer.alloc(0);

const send = (payload) => {
  const json = JSON.stringify(payload);
  const byteLength = Buffer.byteLength(json, "utf8");
  process.stdout.write(`${byteLength} ${json}\n`);
};

const sendOk = (response) => send({ ok: true, response });
const sendError = (err) => send({ ok: false, error: String(err) });

const dispatch = async (body) => {
  let message;
  try {
    message = JSON.parse(body);
  } catch (err) {
    sendError(new SyntaxError(`Invalid JSON: ${err.message}`));
    return;
  }

  const method = message?.method;
  if (typeof method !== "string" || !Object.hasOwn(HANDLERS, method)) {
    sendError(new Error(`Unknown method: ${String(method)}`));
    return;
  }

  try {
    sendOk(await HANDLERS[method](message.params));
  } catch (err) {
    sendError(err);
  }
};

const drain = async () => {
  const isWhitespace = (byte) =>
    byte === 0x20 || byte === 0x0a || byte === 0x0d || byte === 0x09;

  while (true) {
    let start = 0;
    while (start < buffer.length && isWhitespace(buffer[start])) start++;
    buffer = buffer.subarray(start);

    const spaceIndex = buffer.indexOf(0x20);
    if (spaceIndex === -1) return;

    const lengthText = buffer.subarray(0, spaceIndex).toString("ascii");
    if (!/^\d+$/.test(lengthText)) {
      sendError(
        new Error(`Invalid length prefix: ${JSON.stringify(lengthText)}`),
      );
      buffer = Buffer.alloc(0);
      return;
    }

    const length = Number(lengthText);
    const bodyStart = spaceIndex + 1;
    const bodyEnd = bodyStart + length;
    if (buffer.length < bodyEnd) return;

    const body = buffer.subarray(bodyStart, bodyEnd).toString("utf8");
    buffer = buffer.subarray(bodyEnd);
    await dispatch(body);
  }
};

process.stdin.on("data", (chunk) => {
  buffer = Buffer.concat([buffer, chunk]);
  drain();
});
