import { getAddress } from "viem";

const etfAddress = getAddress("0x53B79f1B9be16Ae995f8f95fDeA90F50c84C6475");
const usdcAddress = getAddress("0x22e18Fc2C061f2A500B193E5dBABA175be7cdD7f");
const wethAddress = getAddress("0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14");
const etfQuoterAddress = getAddress(
  "0xF6Fd1703cF0C71221e71Fc08163Da1a38bB777a7"
);

export { etfAddress, usdcAddress, wethAddress, etfQuoterAddress };
