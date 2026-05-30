export async function reverseGeocode(lat, lon) {
  try {
    const url = `https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat=${encodeURIComponent(lat)}&lon=${encodeURIComponent(lon)}&accept-language=ko`;
    const resp = await fetch(url, {
      method: "GET",
      headers: {
        // Nominatim requests a valid Referer or email for identification; include origin as Referer when available
        Referer: typeof location !== "undefined" ? location.origin : undefined
      }
    });
    if (!resp.ok) throw new Error("geocode-failed");
    const data = await resp.json();
    // Prefer display_name, fallback to address components
    if (data.display_name) return data.display_name;
    if (data.address) {
      const a = data.address;
      return [a.road, a.suburb, a.city, a.state, a.country].filter(Boolean).join(", ");
    }
    return `${lat}, ${lon}`;
  } catch (err) {
    throw err;
  }
}
