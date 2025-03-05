import "@rainbow-me/rainbowkit/styles.css";
import "../Tab.css";
import { useState } from "react";
import { InvestTabMulti } from "./InvestTabMulti";
import { RedeemTabMulti } from "./RedeemTabMulti";
import { InvestTabSingle } from "./InvestTabSingle";
import { RedeemTabSingle } from "./RedeemTabSingle";

export const InvestRedeemTabs = () => {
  const [activeTab, setActiveTab] = useState("invest");
  const [useUnderlyingAssets, setUseUnderlyingAssets] = useState(true);

  return (
    <div className="card">
      <div className="tab-header">
        <button
          className={activeTab === "invest" ? "active" : ""}
          onClick={() => setActiveTab("invest")}
        >
          Invest
        </button>
        <button
          className={activeTab === "redeem" ? "active" : ""}
          onClick={() => setActiveTab("redeem")}
        >
          Redeem
        </button>
      </div>
      {/* Switch */}
      <div className="switch-container">
        <label className="switch">
          <input
            type="checkbox"
            checked={useUnderlyingAssets}
            onChange={(e) => setUseUnderlyingAssets(e.target.checked)}
          />
          <span className="slider round"></span>
        </label>
        <label className="form-label">With underlying tokens</label>
      </div>
      {/* Content */}
      <div className="content">
        {activeTab === "invest" ? (
          useUnderlyingAssets ? (
            <InvestTabMulti />
          ) : (
            <InvestTabSingle />
          )
        ) : activeTab === "redeem" ? (
          useUnderlyingAssets ? (
            <RedeemTabMulti />
          ) : (
            <RedeemTabSingle />
          )
        ) : null}
      </div>
    </div>
  );
};
