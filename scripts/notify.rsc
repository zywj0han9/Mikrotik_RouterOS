# TG Bot
## 用法：$sendNotify "message"
:global sendNotify do={
    :local message $1
    # debug
    :local TGBOTTOKEN ""
    :local TGUSERID ""
    :local TGAPIHOST "https://api.telegram.org"
    :put $TGBOTTOKEN
    :put $TGUSERID
    :put $TGAPIHOST
    :put ("MikroTik RouterOS send: $message")

    :local TGAPIURL ($TGAPIHOST . "/bot" . $TGBOTTOKEN . "/sendMessage?chat_id=" . $TGUSERID . "&text=" . $message)

    /tool fetch url=$TGAPIURL mode=https keep-result=no http-method=get

}