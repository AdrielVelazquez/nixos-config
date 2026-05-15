(function (globalScope) {
  const MULTI_PART_PUBLIC_SUFFIXES = new Set([
    "ac.uk",
    "co.il",
    "co.in",
    "co.jp",
    "co.kr",
    "co.nz",
    "co.uk",
    "com.au",
    "com.br",
    "com.cn",
    "com.mx",
    "com.sg",
    "edu.au",
    "edu.cn",
    "edu.in",
    "gov.au",
    "gov.br",
    "gov.cn",
    "gov.in",
    "gov.uk",
    "net.au",
    "net.br",
    "net.cn",
    "net.in",
    "net.uk",
    "org.au",
    "org.br",
    "org.cn",
    "org.in",
    "org.uk",
  ]);

  function isLoopbackIpv4(host) {
    const octets = host.split(".");
    if (octets.length !== 4) {
      return false;
    }

    const numbers = octets.map((octet) => Number.parseInt(octet, 10));
    if (numbers.some((number, index) => String(number) !== octets[index] || number < 0 || number > 255)) {
      return false;
    }

    return numbers[0] === 127 || host === "0.0.0.0";
  }

  function isLocalhost(host) {
    return (
      host === "localhost" ||
      host === "[::1]" ||
      host === "localhost.localdomain" ||
      host.endsWith(".localhost") ||
      host.endsWith(".localhost.localdomain") ||
      isLoopbackIpv4(host)
    );
  }

  function groupNameFromUrl(url) {
    let parsed;

    try {
      parsed = new URL(url);
    } catch {
      return null;
    }

    if (parsed.protocol !== "http:" && parsed.protocol !== "https:") {
      return null;
    }

    const host = parsed.hostname.toLowerCase().replace(/\.$/, "");
    if (!host) {
      return null;
    }

    if (isLocalhost(host)) {
      return "localhost";
    }

    if (!host.includes(".")) {
      return host || null;
    }

    const labels = host.replace(/^www\./, "").split(".").filter(Boolean);
    if (labels.length <= 2) {
      return labels.join(".");
    }

    const suffix = labels.slice(-2).join(".");
    const labelCount = MULTI_PART_PUBLIC_SUFFIXES.has(suffix) ? 3 : 2;

    return labels.slice(-labelCount).join(".");
  }

  globalScope.ZenDomainTabGrouperDomain = {
    groupNameFromUrl,
  };
})(globalThis);
