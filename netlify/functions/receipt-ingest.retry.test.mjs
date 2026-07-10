// Unit tests for visionOcrWithRetry — built-in node:test runner only (zero deps).
// Run: node --test netlify/functions/receipt-ingest.retry.test.mjs
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { visionOcrWithRetry } from './receipt-ingest.js';

// ── Helpers to build injectable single-attempt mocks ──

/** A single-attempt that succeeds with the given text. */
function mockSuccess(text = 'RECEIPT TEXT') {
  let calls = 0;
  return {
    fn: async (_apiKey, _imageBase64, _languageHints) => {
      calls++;
      return { text, failReason: null };
    },
    get calls() { return calls; },
  };
}

/** A single-attempt that fails N times then succeeds. */
function mockFailThenSuccess(failures, failReason, successText = 'RECEIPT TEXT') {
  let calls = 0;
  return {
    fn: async (_apiKey, _imageBase64, _languageHints) => {
      calls++;
      if (calls <= failures) return { text: null, failReason };
      return { text: successText, failReason: null };
    },
    get calls() { return calls; },
  };
}

/** A single-attempt that always fails with the given reason. */
function mockAlwaysFail(failReason) {
  let calls = 0;
  return {
    fn: async (_apiKey, _imageBase64, _languageHints) => {
      calls++;
      return { text: null, failReason };
    },
    get calls() { return calls; },
  };
}

/** A single-attempt that throws (network error). */
function mockThrow(times = 1) {
  let calls = 0;
  return {
    fn: async (_apiKey, _imageBase64, _languageHints) => {
      calls++;
      if (calls <= times) throw new Error('fetch failed');
      return { text: 'RECEIPT TEXT', failReason: null };
    },
    get calls() { return calls; },
  };
}

/** A single-attempt that always throws. */
function mockAlwaysThrow() {
  let calls = 0;
  return {
    fn: async (_apiKey, _imageBase64, _languageHints) => {
      calls++;
      throw new Error('fetch failed');
    },
    get calls() { return calls; },
  };
}

const FAKE_KEY = 'test-key';
const FAKE_IMG = 'base64image';

// ── Tests ──

describe('visionOcrWithRetry', () => {
  it('ok-path: success on first attempt, no retry', async () => {
    const m = mockSuccess('RECEIPT TEXT');
    const r = await visionOcrWithRetry(m.fn, FAKE_KEY, FAKE_IMG);
    assert.equal(r.text, 'RECEIPT TEXT');
    assert.equal(r.failReason, null);
    assert.equal(m.calls, 1);
  });

  it('429 → retry → success', async () => {
    const m = mockFailThenSuccess(1, 'quota', 'RECEIPT TEXT');
    const r = await visionOcrWithRetry(m.fn, FAKE_KEY, FAKE_IMG);
    assert.equal(r.text, 'RECEIPT TEXT');
    assert.equal(r.failReason, null);
    assert.equal(m.calls, 2);
  });

  it('429 → 429 → {text:null, failReason:quota}', async () => {
    const m = mockAlwaysFail('quota');
    const r = await visionOcrWithRetry(m.fn, FAKE_KEY, FAKE_IMG);
    assert.equal(r.text, null);
    assert.equal(r.failReason, 'quota');
    assert.equal(m.calls, 2);
  });

  it('500 → retry → success', async () => {
    const m = mockFailThenSuccess(1, 'http_500', 'RECEIPT TEXT');
    const r = await visionOcrWithRetry(m.fn, FAKE_KEY, FAKE_IMG);
    assert.equal(r.text, 'RECEIPT TEXT');
    assert.equal(r.failReason, null);
    assert.equal(m.calls, 2);
  });

  it('503 → retry → success', async () => {
    const m = mockFailThenSuccess(1, 'http_503', 'RECEIPT TEXT');
    const r = await visionOcrWithRetry(m.fn, FAKE_KEY, FAKE_IMG);
    assert.equal(r.text, 'RECEIPT TEXT');
    assert.equal(r.failReason, null);
    assert.equal(m.calls, 2);
  });

  it('500 → 500 → {text:null, failReason:http_500}', async () => {
    const m = mockAlwaysFail('http_500');
    const r = await visionOcrWithRetry(m.fn, FAKE_KEY, FAKE_IMG);
    assert.equal(r.text, null);
    assert.equal(r.failReason, 'http_500');
    assert.equal(m.calls, 2);
  });

  it('400 → NO retry → {text:null, failReason:http_400}', async () => {
    const m = mockAlwaysFail('http_400');
    const r = await visionOcrWithRetry(m.fn, FAKE_KEY, FAKE_IMG);
    assert.equal(r.text, null);
    assert.equal(r.failReason, 'http_400');
    assert.equal(m.calls, 1); // no retry for 400
  });

  it('403 → NO retry → {text:null, failReason:http_403}', async () => {
    const m = mockAlwaysFail('http_403');
    const r = await visionOcrWithRetry(m.fn, FAKE_KEY, FAKE_IMG);
    assert.equal(r.text, null);
    assert.equal(r.failReason, 'http_403');
    assert.equal(m.calls, 1); // no retry for 403
  });

  it('exception (network error) → retry → success', async () => {
    const m = mockThrow(1);
    const r = await visionOcrWithRetry(m.fn, FAKE_KEY, FAKE_IMG);
    assert.equal(r.text, 'RECEIPT TEXT');
    assert.equal(r.failReason, null);
    assert.equal(m.calls, 2);
  });

  it('exception → exception → {text:null, failReason:exception}', async () => {
    const m = mockAlwaysThrow();
    const r = await visionOcrWithRetry(m.fn, FAKE_KEY, FAKE_IMG);
    assert.equal(r.text, null);
    assert.equal(r.failReason, 'exception');
    assert.equal(m.calls, 2);
  });

  it('empty OCR result → failure after retry (googleVisionOcr returns exception for empty text)', async () => {
    // googleVisionOcr returns {text:null, failReason:'exception'} for empty results.
    const m = mockAlwaysFail('exception');
    const r = await visionOcrWithRetry(m.fn, FAKE_KEY, FAKE_IMG);
    assert.equal(r.text, null);
    assert.equal(r.failReason, 'exception');
    assert.equal(m.calls, 2); // 'exception' is transient → retry fires
  });

  it('retry backoff is at least 1 second', async () => {
    const m = mockFailThenSuccess(1, 'quota', 'OK');
    const start = Date.now();
    await visionOcrWithRetry(m.fn, FAKE_KEY, FAKE_IMG);
    const elapsed = Date.now() - start;
    assert.ok(elapsed >= 1000, `backoff was ${elapsed}ms, expected >= 1000ms`);
  });
});
