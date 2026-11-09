// pako's low-level zlib modules (CommonJS, no types of their own).
declare module "pako/lib/zlib/zstream.js" {
  export default class ZStream {
    input: Uint8Array | null;
    next_in: number;
    avail_in: number;
    output: Uint8Array | null;
    next_out: number;
    avail_out: number;
  }
}
declare module "pako/lib/zlib/inflate.js" {
  import type ZStream from "pako/lib/zlib/zstream.js";
  const zlib: {
    inflateInit(stream: ZStream): number;
    inflate(stream: ZStream, flush: number): number;
    inflateEnd(stream: ZStream): number;
  };
  export default zlib;
}
