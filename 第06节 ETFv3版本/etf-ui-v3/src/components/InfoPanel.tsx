import "../Info.css";
import { etfAbi } from "../abis/etf";
import { erc20Abi } from "../abis/erc20";
import { etfQuoterAbi } from "../abis/etfQuoter";
import { etfAddress, etfQuoterAddress } from "./Constants";
import { useReadContract, useReadContracts } from "wagmi";
import { useEffect, useState, useMemo } from "react";

interface TokenInfo {
  address: string;
  symbol: string;
  decimals: number;
  reserve: string;
  targetWeight: string;
  targetValue: string;
  marketValue: string;
  price: string;
}

export const InfoPanel = () => {
  const [name, setName] = useState<string>("Null");
  const [symbol, setSymbol] = useState<string>("Null");
  const [tvl, setTVL] = useState<string>("0");
  const [totalSupply, setTotalSupply] = useState<string>("0");
  const [investFee, setInvestFee] = useState<string>("0");
  const [redeemFee, setRedeemFee] = useState<string>("0");
  const [lastRebalanceTime, setLastRebalanceTime] = useState<string>("0");
  const [rebalanceInterval, setRebalanceInterval] = useState<string>("0");
  const [tokenInfos, setTokenInfos] = useState<TokenInfo[]>([]);

  const etfContract = {
    abi: etfAbi,
    address: etfAddress,
  };

  // 获取 ETF 的基础数据
  const { data: etfDatas } = useReadContracts({
    contracts: [
      {
        ...etfContract,
        functionName: "name",
      },
      {
        ...etfContract,
        functionName: "symbol",
      },
      {
        ...etfContract,
        functionName: "totalSupply",
      },
      {
        ...etfContract,
        functionName: "investFee",
      },
      {
        ...etfContract,
        functionName: "redeemFee",
      },
      {
        ...etfContract,
        functionName: "lastRebalanceTime",
      },
      {
        ...etfContract,
        functionName: "rebalanceInterval",
      },
    ],
  });

  // 处理 ETF 的基础数据
  useEffect(() => {
    if (etfDatas) {
      const etfName = etfDatas[0].result ?? "Null";
      const etfSymbol = etfDatas[1].result ?? "Null";
      const etfTotalSupply = etfDatas[2].result
        ? (Number(etfDatas[2].result) / 1e18).toString()
        : "0";
      const etfInvestFee = etfDatas[3].result
        ? (Number(etfDatas[3].result) / 10000).toString()
        : "0";
      const etfRedeemFee = etfDatas[4].result
        ? (Number(etfDatas[4].result) / 10000).toString()
        : "0";
      const etfLastRebalanceTime = etfDatas[5].result
        ? new Date(Number(etfDatas[5].result) * 1000).toLocaleString()
        : "N/A";

      let formattedInterval = "";
      const etfRebalanceInterval = etfDatas[6].result;
      if (etfRebalanceInterval !== undefined) {
        if (etfRebalanceInterval >= 86400) {
          // 86400秒 = 1天
          const days = Math.floor(Number(etfRebalanceInterval) / 86400);
          formattedInterval = `${days} days`;
        } else if (etfRebalanceInterval >= 3600) {
          // 3600秒 = 1小时
          const hours = Math.floor(Number(etfRebalanceInterval) / 3600);
          formattedInterval = `${hours} hours`;
        } else {
          const minutes = Math.floor(Number(etfRebalanceInterval) / 60);
          formattedInterval = `${minutes} minutes`;
        }
      }

      setName(etfName);
      setSymbol(etfSymbol);
      setTotalSupply(etfTotalSupply);
      setInvestFee(etfInvestFee);
      setRedeemFee(etfRedeemFee);
      setLastRebalanceTime(etfLastRebalanceTime);
      setRebalanceInterval(formattedInterval);
    }
  }, [etfDatas]);

  // 读取 ETF 合约中的 tokens
  const { data: tokensData } = useReadContract({
    ...etfContract,
    functionName: "getTokens",
  });

  // 构建获取 symbol 和 decimals 的读取请求
  const symbolDecimalsReads = useMemo(() => {
    if (!tokensData || !Array.isArray(tokensData)) {
      return [];
    }

    const symbolCalls = tokensData.map((tokenAddress: string) => ({
      address: tokenAddress as `0x${string}`,
      abi: erc20Abi,
      functionName: "symbol",
    }));

    const decimalsCalls = tokensData.map((tokenAddress: string) => ({
      address: tokenAddress as `0x${string}`,
      abi: erc20Abi,
      functionName: "decimals",
    }));

    return [...symbolCalls, ...decimalsCalls];
  }, [tokensData]);

  // 使用 useReadContracts 获取 symbol 和 decimals
  const { data: symbolDecimalsData } = useReadContracts({
    contracts: symbolDecimalsReads,
  });

  // 读取 ETF 合约的 getTokenMarketValues 和 ETFQuoter 合约的 getTokenTargetValues
  const { data: multiArraysData } = useReadContracts({
    contracts: [
      { ...etfContract, functionName: "getTokenMarketValues" },
      {
        abi: etfQuoterAbi,
        address: etfQuoterAddress,
        functionName: "getTokenTargetValues",
        args: [etfAddress],
      },
    ],
  });

  useEffect(() => {
    if (
      symbolDecimalsData &&
      Array.isArray(symbolDecimalsData) &&
      tokensData &&
      Array.isArray(tokensData) &&
      multiArraysData &&
      multiArraysData[0].status === "success" &&
      multiArraysData[1].status === "success"
    ) {
      const tokenPrices = multiArraysData[0].result[1];
      const tokenMarketValues = multiArraysData[0].result[2];
      const totalValue = (Number(multiArraysData[0].result[3]) / 1e8)
        .toFixed(2)
        .toString();
      const tokenTargetWeights = multiArraysData[1].result[0];
      const tokenTargetValues = multiArraysData[1].result[1];
      const tokenReserves = multiArraysData[1].result[2];

      const tokensWithInfos: TokenInfo[] = tokensData.map((token, index) => {
        const symbol = symbolDecimalsData[index]?.result as string;
        const decimals = symbolDecimalsData[tokensData.length + index]
          ?.result as number;
        const reserve = (Number(tokenReserves[index]) / 1e8)
          .toFixed(2)
          .toString();
        const targetWeight = (Number(tokenTargetWeights[index]) / 10000)
          .toFixed(2)
          .toString();
        const targetValue = (Number(tokenTargetValues[index]) / 1e8)
          .toFixed(2)
          .toString();
        const marketValue = (Number(tokenMarketValues[index]) / 1e8)
          .toFixed(2)
          .toString();
        const price = (Number(tokenPrices[index]) / 1e8).toFixed(2).toString();

        return {
          address: token,
          symbol,
          decimals,
          reserve,
          targetWeight,
          targetValue,
          marketValue,
          price,
        };
      });

      setTokenInfos(tokensWithInfos);
      setTVL(totalValue);
    }
  }, [multiArraysData, symbolDecimalsData, tokensData]);

  return (
    <div className="card">
      <h2>
        {name}({symbol})
      </h2>
      <div className="about-section">
        <h2>About</h2>
        <div className="about-content">
          <div className="info-item">
            <p className="value">${tvl}</p>
            <p className="label">TVL</p>
          </div>
          <div className="info-item">
            <p className="value">{totalSupply}</p>
            <p className="label">Total Supply</p>
          </div>
          <div className="info-item">
            <p className="value">{investFee}%</p>
            <p className="label">Invest Fee</p>
          </div>
          <div className="info-item">
            <p className="value">{redeemFee}%</p>
            <p className="label">Redeem Fee</p>
          </div>
          <div className="info-item">
            <p className="value">{lastRebalanceTime}</p>
            <p className="label">Last Rebalance Time</p>
          </div>
          <div className="info-item">
            <p className="value">{rebalanceInterval}</p>
            <p className="label">Reblance Interval</p>
          </div>
        </div>
      </div>
      <div className="portfolio-table-section">
        <h2>Portfolio</h2>
        <table className="portfolio-table">
          <thead>
            <tr>
              <th>Token</th>
              <th>Reserve</th>
              <th>Target Weight</th>
              <th>Target Value</th>
              <th>Market Value</th>
              <th>Price</th>
            </tr>
          </thead>
          <tbody>
            {tokenInfos.map((item, index) => (
              <tr key={index}>
                <td>{item.symbol}</td>
                <td>{item.reserve}</td>
                <td>{item.targetWeight}%</td>
                <td>${item.targetValue}</td>
                <td>${item.marketValue}</td>
                <td>${item.price}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
};
