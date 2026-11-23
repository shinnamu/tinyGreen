# tg-indicator.otf — 재생성

메뉴바 입력 소스 박스(`IndicatorImages.drawBox`)가 그리는 글자만 담은 Pretendard 서브셋.
1.5MB → 1.7KB. "작고 단순" 정신 + OFL Reserved Font Name 회피용 family 리네임.

- **원본**: Pretendard SemiBold, 공식 repo `orioncactus/pretendard`, SIL OFL-1.1
  (전문: 같은 폴더 `OFL-Pretendard.txt`). 임베드/수정/서브셋 허용.
- **내부 family**: `tinyGreen Indicator` (RFN 'Pretendard' 회피 — 코드의
  `NSFont(name:)` 가 이 이름으로 로드).
- **빌드 의존 0**: 이 파일을 정적 커밋. 서브셋 도구는 빌드타임에 안 씀
  (cleanup 가 python3 뺀 그 원칙과 동일 — 재생성은 수동·문서화된 단발 작업).

## 언어 추가 시 (예: 일본어 'あ' / 중국어 '中' 인디케이터)

`--text` 에 글자만 추가해 재실행 후 결과를 이 폴더에 덮어쓰고 커밋:

```bash
cd /tmp && mkdir -p pw && cd pw
curl -sL -o P.otf "https://github.com/orioncactus/pretendard/raw/main/packages/pretendard/dist/public/static/Pretendard-SemiBold.otf"
pyftsubset P.otf --text="한Aあ中" --output-file=tg-indicator.otf --notdef-outline --no-hinting --desubroutinize
python3 - <<'PY'
from fontTools.ttLib import TTFont
f=TTFont("tg-indicator.otf")
FAM="tinyGreen Indicator"; SUB="SemiBold"; FULL=FAM+" "+SUB; PS="tinyGreenIndicator-SemiBold"
nm=f["name"]
for nid,val in [(1,FAM),(2,SUB),(4,FULL),(6,PS),(16,FAM),(17,SUB)]:
    nm.setName(val,nid,3,1,0x409); nm.setName(val,nid,1,0,0)   # win + mac record
o=f["OS/2"]; o.usWeightClass=600
o.fsSelection = o.fsSelection & ~0x41                          # clear REGULAR(0x40)+ITALIC(0x01)
f["head"].macStyle &= ~0b11                                    # clear bold/italic
f.save("tg-indicator.otf")
PY
# → tinyGreen/Resources/Fonts/tg-indicator.otf 로 복사 후 커밋
```

fonttools 필요(`pip install fonttools`) — 빌드가 아니라 이 재생성 때만.
