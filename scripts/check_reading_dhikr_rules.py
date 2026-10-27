"""Check Quran/Dhikr isolation against a running local Firestore emulator.

Start it with --project_id demo-ummah --rules firestore.rules --port 8787,
then run this script. Uses synthetic credentials and test records only.
"""

import base64
import json
import time
import urllib.error
import urllib.request


BASE = "http://127.0.0.1:8787/v1/projects/demo-ummah/databases/(default)/documents"


def token(uid):
    def encode(value):
        return base64.urlsafe_b64encode(json.dumps(value).encode()).decode().rstrip("=")

    now = int(time.time())
    return ".".join([
        encode({"alg": "none", "typ": "JWT"}),
        encode({"iss": "https://securetoken.google.com/demo-ummah",
                "aud": "demo-ummah", "sub": uid, "user_id": uid,
                "iat": now, "exp": now + 3600,
                "firebase": {"sign_in_provider": "password"}}),
        "",
    ])


def request(method, path, uid, body=None, expected=200):
    headers = {"Content-Type": "application/json"}
    if uid is not None:
        headers["Authorization"] = f"Bearer {token(uid)}"
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(BASE + path, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=15) as response:
            status, payload = response.status, response.read()
    except urllib.error.HTTPError as error:
        status, payload = error.code, error.read()
    assert status == expected, f"{method} {path}: expected {expected}, got {status}"
    return json.loads(payload) if payload else None


def check_collection(parent, child):
    path = f"/{parent}/rules-owner/{child}"
    day = path + "/2026-10-26"
    old_day = path + "/2026-10-18"
    body = {"fields": {"date": {"stringValue": "2026-10-26"},
                       "counts": {"mapValue": {"fields": {
                           "one": {"integerValue": "3"}}}}}}
    request("PATCH", day, "rules-owner", body)
    request("PATCH", old_day, "rules-owner", body)
    request("GET", day, "rules-owner")
    request("GET", day, "rules-other", expected=403)
    request("GET", day, None, expected=403)
    request("PATCH", day, "rules-other", body, expected=403)
    query = {"structuredQuery": {
        "from": [{"collectionId": child}],
        "where": {"compositeFilter": {"op": "AND", "filters": [
            {"fieldFilter": {"field": {"fieldPath": "__name__"},
                             "op": "GREATER_THAN_OR_EQUAL",
                             "value": {"referenceValue": BASE.split("/v1/")[1] + path + "/2026-10-20"}}},
            {"fieldFilter": {"field": {"fieldPath": "__name__"},
                             "op": "LESS_THAN_OR_EQUAL",
                             "value": {"referenceValue": BASE.split("/v1/")[1] + day}}},
        ]}},
    }}
    results = request("POST", f"/{parent}/rules-owner:runQuery", "rules-owner", query)
    names = [item["document"]["name"] for item in results if "document" in item]
    assert names == [BASE.split("/v1/")[1] + day], names
    request("POST", f"/{parent}/rules-owner:runQuery", "rules-other", query, expected=403)
    request("DELETE", day, "rules-owner")
    request("DELETE", old_day, "rules-owner")
    print(f"PASS {parent}: owner access, date bounds, anonymous and cross-user denial")


if __name__ == "__main__":
    check_collection("userQuran", "dailyReading")
    check_collection("userDhikr", "dailyDhikr")
