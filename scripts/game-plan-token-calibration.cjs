#!/usr/bin/env node
/*
 * Development-only calibration for Core's GamePlanTokenEstimator
 * (docs/features/OPPONENT_GAME_PLAN_PROPOSAL.md §11).
 *
 * Counts reference tokens for text fixtures with externally installed
 * tokenizer packages. Nothing here ships in the app, and the app never
 * contacts a service to estimate size.
 *
 *   npm install --prefix /tmp/tok @anthropic-ai/tokenizer@0.0.4 js-tiktoken@1.0.12
 *   CLAUDE_TOKENIZER_MODULE=/tmp/tok/node_modules/@anthropic-ai/tokenizer \
 *   TIKTOKEN_MODULE=/tmp/tok/node_modules/js-tiktoken \
 *   node scripts/game-plan-token-calibration.cjs fixture1.txt fixture2.txt …
 *
 * Representative pack fixtures can be written with
 *   GAME_PLAN_CALIBRATION_OUTPUT=/tmp/gp swift test --filter test_writeCalibrationFixtures
 * (from DeuceMate/Packages/DeuceMateCore). Compare the JSON printed here with
 * GamePlanTokenEstimator.estimate on the same files, then update the pinned
 * reference counts in GamePlanTokenEstimatorTests.swift.
 */
"use strict";

const fs = require("node:fs");
const path = require("node:path");

const claudeModule = process.env.CLAUDE_TOKENIZER_MODULE;
const tiktokenModule = process.env.TIKTOKEN_MODULE;
if (!claudeModule || !tiktokenModule) {
  console.error("Set CLAUDE_TOKENIZER_MODULE and TIKTOKEN_MODULE (see the header).");
  process.exit(2);
}
const files = process.argv.slice(2);
if (files.length === 0) {
  console.error("Pass one or more UTF-8 text files.");
  process.exit(2);
}

const { countTokens } = require(claudeModule);
const { getEncoding } = require(tiktokenModule);
const o200k = getEncoding("o200k_base");
const cl100k = getEncoding("cl100k_base");

const result = {};
for (const file of files) {
  const text = fs.readFileSync(file, "utf8");
  result[path.basename(file)] = {
    chars: [...text].length,
    bytes: Buffer.byteLength(text, "utf8"),
    claudeLegacy: countTokens(text),
    o200k: o200k.encode(text).length,
    cl100k: cl100k.encode(text).length
  };
}
console.log(JSON.stringify(result, null, 2));
