# Herdr Glow

**Herdr 에이전트가 나를 기다릴 때 화면 가장자리가 은은하게 빛나는 앰비언트 라이트.**

[English](README.en.md)

![Herdr 에이전트가 blocked일 때 화면 가장자리에서 주황색 글로우가 숨쉬듯 번지는 모습](assets/herdr-glow-demo.gif)

[Herdr](https://herdr.dev)의 코딩 에이전트가 `blocked`(승인이나 질문 대기) 상태가 되면,
화면 가장자리가 부드럽게 숨쉬듯 빛납니다. 모든 Space, 모니터, 전체화면 앱 위에 표시되고
클릭이나 키보드 포커스는 가로채지 않습니다.

자리를 비웠을 때 놓치지 않게 하면서, 자리에 있을 때는 방해하지 않도록 만들었어요.

1. **짧은 알림.** 에이전트가 blocked가 되면 글로우가 두 번 숨쉬고(약 5.6초) 사라집니다.
2. **자리를 비우면 다시 켜짐.** 여전히 blocked인 상태에서 키보드와 마우스를 30초 동안
   건드리지 않으면 글로우가 다시 켜져서 계속 숨쉽니다.
3. **입력하면 꺼짐.** 키보드나 마우스를 만지면 페이드 아웃합니다. 그 상태로 다시
   자리를 비우면 30초 뒤에 또 켜집니다.
4. **blocked가 풀리면 종료.** blocked인 에이전트가 없어지거나 해당 pane이 닫히면 사라집니다.

blocked가 되는 시점에 이미 자리를 비운 상태라면 짧은 알림 없이 바로 켜집니다.
blocked인 에이전트가 여러 개여도 글로우는 하나만 뜨고, 마지막 하나가 풀릴 때 꺼집니다.

에이전트가 blocked나 done이 되면 화면 아래쪽 가운데에 알약 모양 토스트도 4초간 떠서
어떤 에이전트인지 알려 줍니다(예: `herdr-glow · Claude  is done`).

## 빠른 시작

요구 사항:

- macOS
- 실행 중인 [Herdr](https://herdr.dev) 0.9.0 이상
- Xcode Command Line Tools (`xcode-select --install`). 작은 Swift 헬퍼를 컴파일하는 데 필요합니다.

```sh
herdr plugin install DevooKim/herdr-glow
```

이게 전부예요. 설치하면 헬퍼를 빌드하고 바로 에이전트 상태 변화에 반응합니다.
따로 설정할 액션이나 단축키는 없습니다.

제거하려면:

```sh
herdr plugin uninstall devookim.herdr-glow
```

## 글로우 끄기

blocked가 풀리면 글로우가 꺼집니다. 그래도 남아 있으면
`dismiss` 액션으로 강제로 끌 수 있어요. 상태가 다시 바뀌기 전까지는 켜지지 않습니다.

```sh
herdr plugin action invoke devookim.herdr-glow.dismiss
```

단축키로 쓰려면 Herdr `config.toml`에 추가하세요.

```toml
[[keys.command]]
key = "prefix+g"
type = "plugin_action"
command = "devookim.herdr-glow.dismiss"
description = "dismiss glow"
```

## 데모 실행

현재 `config.toml` 설정 그대로 상태별 글로우와 토스트를 미리 볼 수 있어요.
실제 pane 상태는 건드리지 않습니다. `pulse`가 0이고 `toast`도 꺼진 상태는 "no glow, no toast" 토스트만 뜹니다.

```sh
herdr plugin action invoke devookim.herdr-glow.demo-blocked
herdr plugin action invoke devookim.herdr-glow.demo-done
herdr plugin action invoke devookim.herdr-glow.demo-working
herdr plugin action invoke devookim.herdr-glow.demo-idle
```

## 토스트 클릭

토스트는 기본 4초 동안 떠 있고(`[toast] duration`), 클릭하면 해당 에이전트의 pane으로 이동합니다(`herdr agent focus`, `[toast] click = false`로 끌 수 있어요).
토스트 본문을 클릭하면 pane 전환 후 Herdr를 실행 중인 터미널 앱도 앞으로 가져옵니다. 터미널 앱은 실행 환경의 앱 식별자나 실행 경로로 찾습니다.
여러 터미널을 함께 쓸 때는 앱 식별자와 `TERM_PROGRAM`을 실행 경로보다 우선합니다. 경로 정보만 있고 서로 다른 앱을 가리키면 터미널 앱을 임의로 활성화하지 않습니다.
이동에 성공하면 켜져 있는 글로우도 페이드 아웃합니다. 유휴 감시 중인 글로우는 다시 자리를 비우면 설정한 유휴 시간에 따라 켜집니다.
오른쪽 **X** 버튼을 누르면 토스트를 닫고 글로우도 페이드 아웃합니다. Herdr로 이동하지 않으며, 클릭 이동을 꺼두거나 연결된 pane이 없는 토스트에서도 사용할 수 있어요. 유휴 감시는 계속되므로 다시 자리를 비우면 설정한 유휴 시간에 따라 글로우가 켜질 수 있습니다.
토스트 테두리는 표시 시간에 맞춰 위쪽 중앙부터 시계 방향으로 채워집니다. 끝까지 차면 토스트가 페이드 아웃합니다. X를 포함한 토스트 영역에 마우스를 올리면 테두리가 밝아지고 게이지와 종료 타이머가 함께 멈춥니다. 클릭 가능한 영역에서는 포인터가 손가락 모양으로 바뀝니다. 마우스를 벗어나면 남은 시간부터 다시 진행합니다.
데모 토스트도 클릭하면 지금 보고 있는 에이전트 pane으로 이동하므로 클릭과 hover 효과를 미리 시험해 볼 수 있어요.

## 동작 방식

플러그인이 Herdr의 `pane.agent_status_changed`, `pane.closed`, `pane.exited` 이벤트를
구독합니다. `bin/on-status-changed.sh`가 blocked/done인 pane을 추적하면서 `bin/glow`를 띄우고
종료하고, 상태가 새로 바뀐 pane이 있으면 `bin/toast`(`src/toast.swift`)를 띄웁니다. 토스트는
`herdr agent get`, `herdr workspace get`으로 에이전트와 워크스페이스 이름을 조회합니다. `bin/glow`는 Swift/AppKit으로 작성한 단일 파일 헬퍼(`src/glow.swift`)입니다.

`glow`는 에이전트가 blocked인 동안에만 실행됩니다. 가장자리에 그라디언트를 그린 투명한
클릭 통과 창을 띄우고, 1초마다 시스템 유휴 시간을 확인하며, 훅이 종료 신호를 보내면
페이드 아웃하고 끝납니다. 별도 권한은 필요 없고, 실행 중 메모리는 약 40MB, CPU는
측정되지 않을 만큼 적게 씁니다.

## 설정 바꾸기

`settings` 액션으로 설정 팝업을 열 수 있어요. 상태별 글로우 시간, 유휴 시간, 토스트 표시,
색상과 공통 글로우·토스트 설정을 편집하고 **Save**를 누르면 `config.toml`에 저장됩니다.
**Cancel**이나 창 닫기는 변경 내용을 저장하지 않습니다.

설정 팝업은 macOS의 기본 언어가 한국어이면 한국어로, 그 외에는 영어로 표시됩니다.
한국어에서는 **저장**과 **취소** 버튼으로 표시됩니다. 언어를 변경했다면 설정 창을 닫았다가 다시 열어 주세요.

상태별 색상칸을 클릭하면 macOS 색상 팔레트가 열립니다. 옆의 빨강·파랑·주황·초록 프리셋을
클릭해 바로 선택하거나 HEX 코드를 직접 입력할 수도 있습니다. 선택한 색과 HEX 코드는 함께 갱신되며,
**저장**을 눌러야 설정 파일에 반영됩니다.

각 상태의 **테스트** 버튼으로 저장 전 입력값을 사용해 글로우를 바로 확인할 수 있어요.
색상·알림 시간·두께·디스플레이 설정이 적용되며, 알림 시간이 `0`이면 테스트에서는 3초간 표시합니다.
다른 테스트를 누르면 이전 미리보기가 교체되고, 설정 창을 닫으면 미리보기도 종료됩니다.

```sh
herdr plugin action invoke devookim.herdr-glow.settings
```

단축키로 열려면 Herdr `config.toml`에 추가하세요.

```toml
[[keys.command]]
key = "prefix+shift+g"
type = "plugin_action"
command = "devookim.herdr-glow.settings"
description = "Herdr Glow settings"
```

설정 팝업을 다시 호출하면 열린 창이 앞으로 나옵니다. 저장 시 기존 주석과 다른 설정 항목을
보존하며, 창을 연 뒤 파일이 외부에서 변경되었다면 창을 다시 열어야 저장할 수 있습니다.

파일을 직접 편집할 수도 있어요.

플러그인 설정 폴더(`herdr plugin config-dir devookim.herdr-glow`, 보통
`~/.config/herdr/plugins/config/devookim.herdr-glow/`)에 `config.toml`을 두면 됩니다.
상태(`blocked`, `done`, `working`, `idle`)마다 섹션을 하나씩 쓰고, 적지 않은 값은 기본값을 씁니다.
변경 내용은 다음 이벤트부터 반영됩니다.

```toml
[done]
pulse = 3      # 3초 깜박이고
idle = 0       # 자리를 비워도 다시 켜지지 않음

[blocked]
pulse = 5      # 5초 깜박이고
idle = 15      # 15초 동안 입력이 없으면 다시 켜짐

[idle]
pulse = 2
toast = true
color = "8E8E93"

[glow]
width = 60
screen = "active"   # "active" = 마우스가 있는 디스플레이만, "all" = 모든 디스플레이

[toast]
duration = 4   # 토스트가 떠 있는 시간(초)
click = true   # 클릭하면 해당 pane으로 이동
```

| 키 | 설명 |
| --- | --- |
| `pulse` | 상태가 바뀔 때 깜박이는 시간(초). `0`이면 글로우 없음 |
| `idle` | 그 상태가 이어지는 동안, 이 시간만큼 입력이 없으면 다시 켬(초). `0`이면 다시 켜지 않음 |
| `toast` | 토스트 표시 여부 (`true` / `false`) |
| `color` | 글로우와 토스트 점 색 (`RRGGBB`) |
| `[glow] width` | 글로우 두께(pt) |
| `[glow] screen` | 글로우를 띄울 디스플레이. `active`는 켜지는 순간 마우스가 있는 디스플레이만, `all`은 모든 디스플레이. 기본 `active` |
| `[toast] duration` | 토스트가 떠 있는 시간(초). 기본 `4` |
| `[toast] click` | 토스트를 클릭하면 해당 pane으로 이동 (`true` / `false`). 기본 `true` |

| 상태 | `pulse` | `idle` | `toast` | `color` |
| --- | --- | --- | --- | --- |
| `blocked` | `5.6` | `30` | `true` | `FF8A1F` |
| `done` | `5.6` | `0` | `true` | `34C759` |
| `working` | `0` | `0` | `false` | `0A84FF` |
| `idle` | `0` | `0` | `false` | `8E8E93` |

`idle`이 0보다 큰 상태가 여러 개면 `blocked` → `done` → `working` → `idle` 순으로 우선합니다.

`glow`를 직접 실행해 볼 수도 있어요. `Ctrl+C`나 `pkill glow`로 끕니다.

```sh
bin/glow --duration 0 --width 60
```

`src/*.swift`를 수정했다면 다음 명령으로 다시 빌드하세요.

```sh
swiftc -O src/glow.swift -o bin/glow && swiftc -O src/toast.swift -o bin/toast && swiftc -O src/settings.swift -o bin/settings
```

## 제한 사항

- macOS 전용입니다. 오버레이에 AppKit을 사용합니다.
- 글로우는 실행 시점에 연결된 디스플레이에만 표시됩니다. 기본값(`screen = "active"`)에서는 켜지는 순간 마우스가 있는 디스플레이에만 나옵니다.
- 기본값으로는 `blocked`(주황)와 `done`(초록)에만 반응합니다. 상태별 동작은 [설정 바꾸기](#설정-바꾸기)에서 바꿀 수 있어요. 상태가 바뀌면 이전 글로우를 페이드 아웃하고 새 상태의 색상과 알림 시간으로 표시합니다. 여러 에이전트가 있으면 가장 최근 상태 변경의 알림을 먼저 표시하고, 이후 유휴 알림은 상태 우선순위를 따릅니다.

## 라이선스

MIT
