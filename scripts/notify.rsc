# TG Bot
## 用法：$sendNotify "message"
:global sendNotify do={
    :local message $1
    # debug
    :local TGBOTTOKEN "7804964480:AAELoNlf4nNxc3I5r7Wc661lzadyJv7Ldpw"
    :local TGUSERID "-1002134942278"
    :local TGAPIHOST "https://api.telegram.org"
    :put $TGBOTTOKEN
    :put $TGUSERID
    :put $TGAPIHOST
    :put ("MikroTik RouterOS send: $message")

    :local TGAPIURL ($TGAPIHOST . "/bot" . $TGBOTTOKEN . "/sendMessage?chat_id=" . $TGUSERID . "&text=" . $message)

    /tool fetch url=$TGAPIURL mode=https keep-result=no http-method=get

}