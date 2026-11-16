type ConfigError = object of Exception
echo ConfigError(msg: "x").msg
