# Shardmates

Shardmates helps you quest together with other players in WoW Forever without getting thrown into another layer.

A quest mob in Forever counts only for the player who tagged it, and joining a stranger's group moves you into the leader's layer, where the mobs you just cleared are alive again. Shardmates finds nearby players who use the addon and share your unfinished quests, shows whether grouping up actually helps, and arranges the invite so that the right person moves.

## Features

- **Players on your quests.** A window lists nearby Shardmates users who share your unfinished quests in the zone. Each shared quest is marked "kill credit shared", "event shared" or "you split the drops", so you know what a group gives you before you join one.
- **Layer aware.** Shardmates detects your layer from nearby NPCs and shows whether each player is in the same layer. Since the invited player moves into the leader's world, the addon decides who invites whom and tells you in advance who will move.
- **Invites only by agreement.** Click "Invite" or "Ask to join", and the other player sees a "Group up / Not now" prompt. Once both agree, the invite is accepted automatically. Any other invite comes through the usual Blizzard prompt.
- **Tag helper.** If the quest mob you target is already tagged by another player, a button under the target frame offers to invite them, so both of you get credit.
- **Parting ways.** When nothing is left to do together, Shardmates offers "Thanks and leave". During an escort quest it warns you that leaving the group would break the escort.

## Modes

- **Ask me** (default): every request opens a prompt.
- **Automatic**: requests that do not move you into another layer are accepted right away.
- **Off**: the addon sends nothing and declines requests.

## Commands

- `/shardmates` or `/smates`: open the window. The minimap button does the same; right-click it for options.
- `/shardmates mode ask`, `/shardmates mode auto`, `/shardmates mode off`: switch the mode.
- `/shardmates diag`: open a diagnostic report. Please copy it into your bug report.

## What the addon shares

Shardmates exchanges data with other copies of the addon through a hidden chat channel for your zone, with no external servers.

- **Presence**, every 90 seconds and whenever your quests, layer or group change: faction, zone, layer, level, class, group status, mode, your unfinished quests in the zone with their objective types, and a short character ID used to match invites. If you have no matching quests in the zone, nothing is sent.
- **Group requests and answers** go by whisper to one player only.
- Players of the other faction are never listed: their messages are dropped.
- Nothing is sent inside dungeons, and the Off mode stops all sharing.
- Only your settings are saved to disk. Nearby players are kept in memory and forgotten after four minutes without news.

## Good to know

- The layer becomes known once the addon has seen two different NPCs (nameplates, your target or the mouse cursor). Until then it is shown as unknown.
- Only players who have Shardmates installed can be found.
- Languages: English and Russian.

## На русском

Shardmates помогает выполнять задания вместе с другими игроками в WoW Forever так, чтобы никого не перебросило в чужой слой.

В Forever моб на задание засчитывается только тому, кто его тегнул, а вступление в группу к незнакомцу переносит в слой лидера, где только что зачищенные мобы снова живы. Shardmates находит рядом игроков с аддоном, у которых те же невыполненные задания, показывает, выгодна ли группа, и устраивает приглашение так, чтобы переходил нужный игрок.

**Возможности**

- Окно со списком игроков рядом, у которых те же невыполненные задания в зоне. У каждого общего задания пометка "общий кредит за убийство", "общее событие" или "добычу придётся делить".
- Аддон определяет слой по NPC рядом и показывает, в том же ли слое другой игрок. Приглашённый переходит в мир лидера, поэтому аддон сам решает, кто кого приглашает, и заранее пишет, кого перенесёт.
- Приглашение только по согласию: после кнопки "Пригласить" или "Попроситься" второй игрок видит вопрос "Объединиться / Не сейчас". Когда оба согласны, приглашение принимается само. Остальные приглашения приходят обычным окном Blizzard.
- Помощник по тегу: если нужного по заданию моба уже бьёт другой игрок, под рамкой цели появляется кнопка, которая зовёт его в группу, чтобы кредит получили оба.
- Когда общих целей не осталось, аддон предлагает "Поблагодарить и выйти", а во время сопровождения предупреждает, что выход из группы его сорвёт.

**Режимы:** "Спрашивать" (по умолчанию), "Автоматически" (запросы, при которых вас не переносит в другой слой, принимаются сразу) и "Выключен" (аддон ничего не отправляет и отклоняет запросы).

**Команды:** `/shardmates` или `/smates` открывает окно, кнопка у миникарты делает то же, а правый щелчок по ней открывает настройки, `/shardmates mode ask|auto|off` меняет режим, `/shardmates diag` открывает отчёт для сообщения об ошибке.

**Что передаётся.** Обмен идёт через скрытый канал чата вашей зоны, без внешних серверов. Раз в 90 секунд и при смене заданий, слоя или группы уходят фракция, зона, слой, уровень, класс, состояние группы, режим, невыполненные задания зоны с типами целей и короткий номер персонажа для сверки приглашений. Если подходящих заданий в зоне нет, не уходит ничего. Запросы и ответы идут шёпотом одному игроку. Игроков другой фракции аддон не показывает: их сообщения отбрасываются. В подземельях аддон молчит. На диск пишутся только настройки, а игроки рядом хранятся в памяти и забываются через четыре минуты тишины.

**Полезно знать:** слой определяется, когда аддон увидит двух разных NPC (полоски над головой, цель или курсор). Найти можно только игроков, у которых стоит Shardmates. Языки: русский и английский.

## License

Copyright (c) 2026 MRAktiv. All rights reserved, see [LICENSE](LICENSE). The libraries in `Libs` belong to their authors and keep their own licenses.
