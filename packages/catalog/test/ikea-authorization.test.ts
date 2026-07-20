import { test } from "bun:test";
import assert from "node:assert/strict";

import {
  assertIkeaSourceAuthorization,
  REFRAME_IKEA_US_AUTHORIZATION,
} from "../src/ikea-authorization.ts";

test("an enabled recorded IKEA policy permits only its exact market and locale", () => {
  assert.doesNotThrow(() => assertIkeaSourceAuthorization(REFRAME_IKEA_US_AUTHORIZATION));
  assert.throws(
    () =>
      assertIkeaSourceAuthorization({
        ...REFRAME_IKEA_US_AUTHORIZATION,
        locale: "en-GB",
      }),
    /invalid_ikea_authorization_locale/,
  );
});
