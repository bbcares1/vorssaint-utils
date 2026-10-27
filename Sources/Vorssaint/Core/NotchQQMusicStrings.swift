// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct NotchQQMusicStrings {
    let playlist: String
    let connect: String
    let accessHint: String
    let waiting: String
    let noLyrics: String
    let unsupported: String

    init(_ language: AppLanguage) {
        let values: [String]
        switch language {
        case .zhHans:
            values = ["QQ 音乐播放列表", "连接 QQ 音乐", "请选择 QQ 音乐的 QQMusicMac 数据文件夹。仅在此页面打开时读取播放列表和歌词，数据不会上传。", "正在等待 QQ 音乐更新当前歌曲…", "QQ 音乐尚未缓存这首歌的歌词。请在 QQ 音乐打开歌词后重试。", "暂时无法读取此版本 QQ 音乐的播放列表。"]
        case .zhTW, .zhHK:
            values = ["QQ 音樂播放清單", "連接 QQ 音樂", "請選擇 QQ 音樂的 QQMusicMac 資料夾。僅在此頁面開啟時讀取播放清單和歌詞，資料不會上傳。", "正在等待 QQ 音樂更新目前歌曲…", "QQ 音樂尚未快取這首歌的歌詞。請在 QQ 音樂開啟歌詞後重試。", "暫時無法讀取此版本 QQ 音樂的播放清單。"]
        case .ja:
            values = ["QQ Music の再生リスト", "QQ Music に接続", "QQ Music の QQMusicMac データフォルダを選択してください。このページを開いている間だけ再生リストと歌詞を読み取ります。データは送信されません。", "QQ Music の曲情報の更新を待っています…", "歌詞がまだ保存されていません。QQ Music で歌詞を開いてから再試行してください。", "このバージョンの QQ Music の再生リストを読み取れません。"]
        case .ko:
            values = ["QQ Music 재생 목록", "QQ Music 연결", "QQ Music의 QQMusicMac 데이터 폴더를 선택하세요. 이 페이지가 열려 있을 때만 재생 목록과 가사를 읽으며 데이터를 전송하지 않습니다.", "QQ Music의 현재 곡 업데이트를 기다리는 중…", "가사가 아직 캐시되지 않았습니다. QQ Music에서 가사를 연 후 다시 시도하세요.", "이 버전의 QQ Music 재생 목록을 읽을 수 없습니다."]
        case .ptBR:
            values = ["Fila do QQ Music", "Conectar QQ Music", "Selecione a pasta de dados QQMusicMac do QQ Music. A fila e as letras são lidas apenas enquanto esta página está aberta. Nenhum dado é enviado.", "Aguardando o QQ Music atualizar a música…", "A letra ainda não está em cache. Abra a letra no QQ Music e tente novamente.", "Não foi possível ler a fila desta versão do QQ Music."]
        case .tr:
            values = ["QQ Music çalma listesi", "QQ Music'e bağlan", "QQ Music'in QQMusicMac veri klasörünü seçin. Liste ve şarkı sözleri yalnızca bu sayfa açıkken okunur. Veri gönderilmez.", "QQ Music'in şarkıyı güncellemesi bekleniyor…", "Şarkı sözleri henüz önbellekte değil. QQ Music'te sözleri açıp tekrar deneyin.", "Bu QQ Music sürümünün çalma listesi okunamıyor."]
        case .ru:
            values = ["Очередь QQ Music", "Подключить QQ Music", "Выберите папку данных QQMusicMac. Очередь и тексты читаются только при открытой странице. Данные не отправляются.", "Ожидание обновления песни в QQ Music…", "Текст ещё не сохранён. Откройте текст в QQ Music и повторите попытку.", "Не удалось прочитать очередь этой версии QQ Music."]
        case .es:
            values = ["Cola de QQ Music", "Conectar QQ Music", "Selecciona la carpeta de datos QQMusicMac. La cola y las letras se leen solo mientras esta página está abierta. No se envían datos.", "Esperando a que QQ Music actualice la canción…", "La letra aún no está en caché. Ábrela en QQ Music y vuelve a intentarlo.", "No se puede leer la cola de esta versión de QQ Music."]
        case .sk:
            values = ["Zoznam QQ Music", "Pripojiť QQ Music", "Vyberte priečinok údajov QQMusicMac. Zoznam a texty sa čítajú iba pri otvorenej stránke. Údaje sa nikam neposielajú.", "Čaká sa na aktualizáciu skladby v QQ Music…", "Text ešte nie je uložený. Otvorte text v QQ Music a skúste to znova.", "Zoznam tejto verzie QQ Music sa nedá prečítať."]
        case .de:
            values = ["QQ Music-Wiedergabeliste", "QQ Music verbinden", "Wähle den Datenordner QQMusicMac. Wiedergabeliste und Liedtexte werden nur bei geöffneter Seite gelesen. Es werden keine Daten gesendet.", "Warten auf die Aktualisierung des Titels in QQ Music…", "Der Liedtext ist noch nicht gespeichert. Öffne ihn in QQ Music und versuche es erneut.", "Die Wiedergabeliste dieser QQ Music-Version kann nicht gelesen werden."]
        case .fr:
            values = ["File de lecture QQ Music", "Connecter QQ Music", "Sélectionnez le dossier de données QQMusicMac. La file et les paroles sont lues uniquement lorsque cette page est ouverte. Aucune donnée n’est envoyée.", "En attente de la mise à jour du morceau dans QQ Music…", "Les paroles ne sont pas encore en cache. Ouvrez-les dans QQ Music puis réessayez.", "Impossible de lire la file de cette version de QQ Music."]
        case .it:
            values = ["Coda di QQ Music", "Collega QQ Music", "Seleziona la cartella dati QQMusicMac. Coda e testi vengono letti solo mentre questa pagina è aperta. Nessun dato viene inviato.", "In attesa dell’aggiornamento del brano in QQ Music…", "Il testo non è ancora nella cache. Aprilo in QQ Music e riprova.", "Impossibile leggere la coda di questa versione di QQ Music."]
        case .uk:
            values = ["Черга QQ Music", "Підключити QQ Music", "Виберіть папку даних QQMusicMac. Черга та тексти читаються лише на відкритій сторінці. Дані не надсилаються.", "Очікування оновлення пісні в QQ Music…", "Текст ще не збережено. Відкрийте його в QQ Music і спробуйте знову.", "Не вдалося прочитати чергу цієї версії QQ Music."]
        case .enUS:
            values = ["QQ Music playlist", "Connect QQ Music", "Choose QQ Music’s QQMusicMac data folder. The playlist and lyrics are read only while this page is open. Nothing is uploaded.", "Waiting for QQ Music to update the current song…", "QQ Music has not cached these lyrics yet. Open the lyrics in QQ Music, then try again.", "The playlist from this version of QQ Music could not be read."]
        }
        playlist = values[0]; connect = values[1]; accessHint = values[2]
        waiting = values[3]; noLyrics = values[4]; unsupported = values[5]
    }
}
