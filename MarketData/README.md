some Apis for dev

## overview

- url: https://moonswap.fi/api/route/opt/moonswap/overview

- response:

| Name | Description |
| --- | --- |
|liquidity_usd | total liquidity value |
| volume_24h_usd | 24h volume |

```
{
  "liquidity_usd": "31587855.729789036089716400",
  "volume_24h_usd": "2401699.222056322235093031"
}

```

## pairs

- url: https://moonswap.fi/api/route/opt/moonswap/pairs

- response:

```
[
    {
        "ticker_id": "0x86c90add0b8fbe7e4e110aa0b0f4e9582f898496",
        "base": "MOON",
        "target": "ETH"
    },
    {
        "ticker_id": "0x8b375ff098db5757966c653c05ec2655bde1c33f",
        "base": "USDT",
        "target": "ETH"
    }
]

```

## tickers

- url: [https://moonswap.fi/api/route/opt/moonswap/tickers](https://moonswap.fi/api/route/opt/moonswap/tickers "https://moonswap.fi/api/route/opt/moonswap/tickers")

- response:


```
[
    {
        "ticker_id": "0x86c90add0b8fbe7e4e110aa0b0f4e9582f898496",
        "base_currency": "MOON",
        "target_currency": "ETH",
        "last_price": "823.36419585",
        "base_volume": "0.000000",
        "target_volume": "0.000000",
        "high": 988.03703502,
        "low": 658.69135668,
        "bid": 806.896911933,
        "ask": 839.831479767
    },
    {
        "ticker_id": "0x8b375ff098db5757966c653c05ec2655bde1c33f",
        "base_currency": "USDT",
        "target_currency": "ETH",
        "last_price": "373.05922368",
        "base_volume": "0.000000",
        "target_volume": "0.000000",
        "high": 447.67106841599997,
        "low": 298.44737894400004,
        "bid": 365.5980392064,
        "ask": 380.5204081536
    }
]

```

## historical_trades

- url: https://moonswap.fi/api/route/opt/moonswap/trades?ticker_id=0x8689b0c36d65f0cbed051dd36a649d3c68d67b6f&limit=5

- request:

| Name | Description|
| --- | --- |
|ticker_id | get by pairs |
| type | side: buy or sell |
| limit | limit size |


- response:

```
[
    {
        "trade_id": 15152,
        "price": "373.78920860",
        "base_volume": "501.80453677",
        "quote_volume": "1.34248000",
        "trade_timestamp": 1602315863,
        "type": "buy"
    },
    {
        "trade_id": 15140,
        "price": "371.69229573",
        "base_volume": "683.81374972",
        "quote_volume": "1.83973076",
        "trade_timestamp": 1602312964,
        "type": "sell"
    }
]

```
