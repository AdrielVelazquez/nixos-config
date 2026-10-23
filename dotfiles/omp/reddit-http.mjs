export function trustedRedditOrigin(value, allowTestLoopback = false) {
  const root = new URL(value);
  const local = allowTestLoopback && root.protocol === 'http:' && ['127.0.0.1', '[::1]'].includes(root.hostname);
  if ((!local && root.protocol !== 'https:') || root.username || root.password || root.pathname !== '/' || root.search || root.hash) {
    throw new Error('Invalid trusted Reddit control-plane origin');
  }
  return root.origin;
}

/** Callers supply a deadline signal covering both fetching and body decoding. */
export function boundedRedditFetch(origin, fetchImpl = fetch) {
  return async (url, init = {}) => {
    const target = new URL(url);
    if (target.origin !== origin || target.username || target.password || target.search || target.hash) {
      throw new Error('Reddit request escaped its trusted control-plane origin');
    }
    const response = await fetchImpl(target.href, { ...init, redirect: 'error' });
    const reader = response.body?.getReader();
    const chunks = []; let size = 0;
    if (reader) while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > 1024 * 1024) { void reader.cancel(); throw new Error('Reddit response exceeded its metadata limit'); }
      chunks.push(value);
    }
    const body = new Uint8Array(size); let offset = 0;
    for (const chunk of chunks) { body.set(chunk, offset); offset += chunk.byteLength; }
    return new Response([204, 205, 304].includes(response.status) ? null : body, { status: response.status, headers: response.headers });
  };
}
