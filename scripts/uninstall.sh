#!/bin/bash
set -e

APP_NAME="ra1nIME"
BUNDLE_ID="kr.ra1n.inputmethod.ra1nime"

echo "==> ra1n IME 종료 중..."
killall -9 "$APP_NAME" 2>/dev/null || true

# 프로세스가 완전히 종료될 때까지 최대 3초 대기
for i in {1..30}; do
    if ! pgrep -xq "$APP_NAME"; then
        echo "  ✓ 프로세스 종료됨"
        break
    fi
    sleep 0.1
done

echo "==> 시스템 설정 입력 소스 목록에서 제거 중..."
/usr/bin/swift - <<'SWIFT'
import Foundation
let plistPath = NSHomeDirectory() + "/Library/Preferences/com.apple.HIToolbox.plist"
guard let plist = NSMutableDictionary(contentsOfFile: plistPath),
      var sources = plist["AppleEnabledInputSources"] as? [NSMutableDictionary] else {
    exit(0)
}
let before = sources.count
sources.removeAll { dict in
    guard let id = dict["InputSourceID"] as? String else { return false }
    return id.hasPrefix("kr.ra1n.inputmethod.ra1nime")
}
if sources.count < before {
    plist["AppleEnabledInputSources"] = sources
    plist.write(toFile: plistPath, atomically: true)
    print("  ✓ 입력 소스 목록에서 제거됨")
} else {
    print("  (입력 소스 목록에 없음)")
}
SWIFT

echo "==> 앱 번들 삭제 중..."
if [ -d "/Library/Input Methods/${APP_NAME}.app" ]; then
    sudo rm -rf "/Library/Input Methods/${APP_NAME}.app"
    echo "  ✓ /Library/Input Methods/${APP_NAME}.app 삭제됨"
fi
if [ -d "$HOME/Library/Input Methods/${APP_NAME}.app" ]; then
    rm -rf "$HOME/Library/Input Methods/${APP_NAME}.app"
    echo "  ✓ ~/Library/Input Methods/${APP_NAME}.app 삭제됨"
fi

echo "==> LaunchServices 등록 해제..."
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"
"$LSREGISTER" -u "/Library/Input Methods/${APP_NAME}.app" 2>/dev/null || true

echo "==> UserDefaults 정리..."
defaults delete "$BUNDLE_ID" 2>/dev/null && echo "  ✓ 설정값 삭제됨" || true

echo "==> 권한 제거 중..."
tccutil reset All "$BUNDLE_ID" 2>/dev/null && echo "  ✓ 입력 모니터링/손쉬운 사용 권한 제거됨" || true

echo "==> 캐시 데몬 재시작..."
killall cfprefsd TextInputMenuAgent 2>/dev/null || true

echo ""
echo "========================================"
echo "  ra1n IME 제거 완료"
echo "========================================"
echo ""

# 로그아웃 대화상자
RESPONSE=$(osascript -e 'button returned of (display dialog "ra1n IME 제거가 완료되었습니다.

변경사항을 완전히 적용하려면 로그아웃이 필요합니다. 지금 로그아웃하시겠습니까?" buttons {"나중에", "로그아웃"} default button "로그아웃" with icon note)' 2>/dev/null)

if [ "$RESPONSE" = "로그아웃" ]; then
    echo "==> 로그아웃 중..."
    osascript -e 'tell application "System Events" to log out'
fi
