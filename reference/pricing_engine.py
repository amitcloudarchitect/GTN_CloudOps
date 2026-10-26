"""
Getronics CloudOps — pricing, effort and margin engine.

Ported from Public_Cloud_Services_-_Pricing_Calculator_-_2026_-_V2_14.xlsx.
Every constant below is traceable to a named sheet/cell range in that workbook.
The regression tests at the bottom reproduce the workbook's own reference case
(321 critical CIs, 24x7, Gold, India delivery, EUR 43,856/mo consumption).

Design rules:
  - No floats baked into business logic; all rates live in RATE_CARD.
  - Every public function is pure. State lives in the caller.
  - Monetary values are rounded only at the presentation boundary.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Literal

Coverage = Literal["8x5", "16x5", "24x7"]
SupportModel = Literal["Bronze", "Silver", "Gold"]
Location = Literal["India", "Budapest"]


# ---------------------------------------------------------------------------
# RATE CARD  (sheet: Pricing Catalog, Slabs, Base pack Calculation, People Cost)
# ---------------------------------------------------------------------------

# Blended delivery rate per 8-hour day. Pricing Catalog!B1
BLENDED_DAY_RATE_EUR = 266.9932626632895
MINUTES_PER_DAY = 480.0

# Complexity score -> effort minutes per CI per month. Pricing Catalog, cols N:O
COMPLEXITY_MINUTES = {
    1: 3, 2: 5, 3: 6, 4: 10, 5: 25, 6: 30,
    7: 45, 8: 60, 9: 75, 10: 90, 11: 120, "Case": 150,
}

# Combined coverage x support multipliers. Pricing Catalog, cols Q:R.
# NOTE: these are NOT the clean product of the coverage and category conversion
# tables also present on that sheet (24x7 rows carry an extra 1.1 uplift that
# the 16x5/8x5 rows do not). The workbook's own values are authoritative here;
# see docs/adr/0007-pricing-multipliers.md. Flagged for commercial sign-off.
SERVICE_MULTIPLIER = {
    ("24x7", "Gold"): 5.544, ("16x5", "Gold"): 3.96, ("8x5", "Gold"): 3.6,
    ("24x7", "Silver"): 3.542, ("16x5", "Silver"): 2.53, ("8x5", "Silver"): 2.3,
    ("24x7", "Bronze"): 3.08, ("16x5", "Bronze"): 2.2, ("8x5", "Bronze"): 2.0,
}

# Resource type -> complexity. Pricing Catalog col C. Azure/AWS equivalents share a row.
RESOURCE_COMPLEXITY = {
    "AD Domain Services / AWS Managed Microsoft AD": "Case",
    "Microsoft Active Directory IaaS / AD on AWS EC2": "Case",
    "Microsoft Entra ID / AWS IAM Identity Center": 6,
    "Azure Virtual Machines / Amazon EC2": 3,
    "App Service / AWS Elastic Beanstalk": 3,
    "Azure Kubernetes Service (AKS) / Amazon EKS": 5,
    "File Sync / AWS DataSync": 3,
    "MS SQL DB / Azure SQL / Amazon RDS": 4,
    "Event Hubs / Amazon Kinesis": 3,
    "Azure Functions / AWS Lambda": 3,
    "Fileshare / Amazon FSx": 11,
    "Web Application Firewall / AWS WAF": 9,
    "Load Balancer / Elastic Load Balancing": 6,
    "ExpressRoute / AWS Direct Connect": 6,
    "Firewall / AWS Network Firewall": 3,
    "Azure CDN / Amazon CloudFront": 2,
    "Virtual WANs / AWS Transit Gateway": 4,
    "VPN Gateway / AWS Site-to-Site VPN": 6,
    "Application Gateway / AWS ALB": "Case",
    "Azure DevOps / AWS Developer Tools": "Case",
}

# Progressive consumption bands for the base pack. Base pack Calculation!A3:E11
# Applied marginally (each band's rate applies only to spend inside that band).
BASE_PACK_BANDS = [
    (0, 1_000, 0.0),
    (1_000, 5_000, 0.07),
    (5_000, 10_000, 0.055),
    (10_000, 25_000, 0.045),
    (25_000, 50_000, 0.03),
    (50_000, 75_000, 0.02),
    (75_000, 100_000, 0.015),
    (100_000, float("inf"), 0.0085),
]
BASE_PACK_FLOOR_EUR = 250.0                     # Base pack Calculation!B36:B38
BASE_PACK_COVERAGE_UPLIFT = {"8x5": 1.0, "16x5": 1.1, "24x7": 1.4}

# CI-count slabs. Slabs!A3:A8
CI_SLABS = [
    ("0 - 50 CIs", 0, 50, 6),
    ("51 - 150 CIs", 51, 150, 8),
    ("151 - 300 CIs", 151, 300, 10),
    ("301 - 500 CIs", 301, 500, 12),
    ("501 - 1000 CIs", 501, 1000, 14),
    ("> 1001 CIs", 1001, 10**9, 18),
]

# Tooling. Platforms Cost!J5:M8 + CoreStack consumption slab
TOOL_COST_PER_CI_EUR = {"OpsRamp": 4.343, "Qualys": 3.225, "CloudBolt": 7.00}
CORESTACK_CONSUMPTION_RATE = 0.021               # Platforms Cost!K3

# People cost per person per month, fully loaded. People Cost!B25:B27 / E25:E27
PEOPLE_COST_EUR = {"India": 1786.9079747305266, "Budapest": 7878.248133680555}
WORKING_DAYS_PER_MONTH = 18.1                    # People Cost!B28

# Role mix used to convert an FTE count into a named team. Base pack Calculation!G3:H8
ROLE_MIX = {
    "Full Stack Cloud Engineer": 0.45,
    "Cloud Specialist": 0.35,
    "Cloud Architect": 0.10,
    "CloudOps Manager": 0.05,
    "Cloud Delivery Manager": 0.05,
}


# ---------------------------------------------------------------------------
# INPUTS / OUTPUTS
# ---------------------------------------------------------------------------

@dataclass
class Engagement:
    """Everything the engine needs about one customer engagement."""
    customer: str
    inventory: dict[str, int]          # resource type -> CI count
    monthly_consumption_eur: float
    coverage: Coverage = "24x7"
    support_model: SupportModel = "Gold"
    location: Location = "India"
    tools: tuple[str, ...] = ("OpsRamp", "Qualys", "CloudBolt")
    corestack: bool = True
    # From the SOW. None means not yet captured.
    sow_monthly_revenue_eur: float | None = None


@dataclass
class Quote:
    customer: str
    critical_cis: int
    slab: str
    service_cost_eur: float            # effort-driven catalogue cost
    base_pack_eur: float               # consumption-driven managed-service floor
    cloud_services_cost_eur: float     # service + base pack
    platform_cost_eur: float           # tooling
    total_monthly_eur: float
    price_per_ci_eur: float
    fte_count: float
    team: dict[str, float] = field(default_factory=dict)
    transition_weeks: int = 0
    transition_effort_days: int = 0


# ---------------------------------------------------------------------------
# CORE CALCULATIONS
# ---------------------------------------------------------------------------

def effort_minutes_for(resource_type: str) -> float:
    """Monthly effort minutes per CI, from the complexity score."""
    complexity = RESOURCE_COMPLEXITY[resource_type]
    return float(COMPLEXITY_MINUTES[complexity])


def unit_price(resource_type: str, coverage: Coverage, support: SupportModel) -> float:
    """Monthly catalogue price for one CI of this type."""
    minutes = effort_minutes_for(resource_type)
    base = minutes * (BLENDED_DAY_RATE_EUR / MINUTES_PER_DAY)
    return base * SERVICE_MULTIPLIER[(coverage, support)]


def service_cost(inventory: dict[str, int], coverage: Coverage, support: SupportModel) -> float:
    return sum(unit_price(rt, coverage, support) * n for rt, n in inventory.items() if n)


def base_pack(consumption_eur: float, coverage: Coverage) -> float:
    """Marginal-band percentage of consumption, plus the floor, uplifted for coverage."""
    total = 0.0
    for lower, upper, rate in BASE_PACK_BANDS:
        if consumption_eur <= lower:
            break
        total += (min(consumption_eur, upper) - lower) * rate
    return (total + BASE_PACK_FLOOR_EUR) * BASE_PACK_COVERAGE_UPLIFT[coverage]


def slab_for(ci_count: int) -> tuple[str, int]:
    """Returns (slab label, transition weeks)."""
    for label, lo, hi, weeks in CI_SLABS:
        if lo <= ci_count <= hi:
            return label, weeks
    return CI_SLABS[-1][0], CI_SLABS[-1][3]


def platform_cost(ci_count: int, consumption_eur: float,
                  tools: tuple[str, ...], corestack: bool) -> float:
    licence = sum(TOOL_COST_PER_CI_EUR[t] * ci_count for t in tools)
    governance = consumption_eur * CORESTACK_CONSUMPTION_RATE if corestack else 0.0
    return licence + governance


def fte_count(cloud_services_cost_eur: float, location: Location) -> float:
    """Implied team size: service cost divided by fully loaded cost per head."""
    return cloud_services_cost_eur / PEOPLE_COST_EUR[location]


def build_team(fte: float) -> dict[str, float]:
    return {role: round(fte * share, 3) for role, share in ROLE_MIX.items()}


def quote(e: Engagement) -> Quote:
    cis = sum(e.inventory.values())
    slab_label, weeks = slab_for(cis)
    svc = service_cost(e.inventory, e.coverage, e.support_model)
    bp = base_pack(e.monthly_consumption_eur, e.coverage)
    cloud_services = svc + bp
    platforms = platform_cost(cis, e.monthly_consumption_eur, e.tools, e.corestack)
    total = cloud_services + platforms
    fte = fte_count(cloud_services, e.location)
    return Quote(
        customer=e.customer,
        critical_cis=cis,
        slab=slab_label,
        service_cost_eur=svc,
        base_pack_eur=bp,
        cloud_services_cost_eur=cloud_services,
        platform_cost_eur=platforms,
        total_monthly_eur=total,
        price_per_ci_eur=total / cis if cis else 0.0,
        fte_count=fte,
        team=build_team(fte),
        transition_weeks=weeks,
        transition_effort_days=weeks * 5,
    )


# ---------------------------------------------------------------------------
# MARGIN  (the part the workbook cannot do: modelled cost vs SOW revenue)
# ---------------------------------------------------------------------------

@dataclass
class MarginResult:
    customer: str
    revenue_eur: float
    modelled_cost_eur: float
    actual_cost_eur: float | None
    gross_margin_pct: float
    variance_vs_model_eur: float | None
    health: str


def margin(e: Engagement, q: Quote, actual_effort_hours: float | None = None) -> MarginResult:
    """
    Modelled cost  = implied FTE x loaded people cost + tooling.
    Actual cost    = observed effort hours x loaded day rate / 8 + tooling,
                     where effort hours come from ServiceNow (incident duration,
                     change tasks, project tasks, service requests).
    The gap between the two is where margin leaks.
    """
    if e.sow_monthly_revenue_eur is None:
        raise ValueError(f"{e.customer}: SOW revenue not captured")

    modelled = q.fte_count * PEOPLE_COST_EUR[e.location] + q.platform_cost_eur

    actual = None
    variance = None
    if actual_effort_hours is not None:
        day_rate = PEOPLE_COST_EUR[e.location] / WORKING_DAYS_PER_MONTH
        actual = (actual_effort_hours / 8.0) * day_rate + q.platform_cost_eur
        variance = actual - modelled

    cost_basis = actual if actual is not None else modelled
    gm = (e.sow_monthly_revenue_eur - cost_basis) / e.sow_monthly_revenue_eur

    if gm < 0.10:
        health = "critical"
    elif gm < 0.20:
        health = "at risk"
    elif gm < 0.30:
        health = "watch"
    else:
        health = "healthy"

    return MarginResult(
        customer=e.customer,
        revenue_eur=e.sow_monthly_revenue_eur,
        modelled_cost_eur=modelled,
        actual_cost_eur=actual,
        gross_margin_pct=gm,
        variance_vs_model_eur=variance,
        health=health,
    )


def slab_headroom(ci_count: int) -> dict:
    """How close is this customer to a repricing boundary?"""
    label, _ = slab_for(ci_count)
    for i, (lbl, lo, hi, _) in enumerate(CI_SLABS):
        if lbl == label:
            nxt = CI_SLABS[i + 1][0] if i + 1 < len(CI_SLABS) else None
            remaining = hi - ci_count
            return {
                "current_slab": label,
                "next_slab": nxt,
                "cis_until_next_slab": remaining if nxt else None,
                "repricing_due": bool(nxt) and remaining <= max(10, 0.05 * (hi - lo)),
            }
    return {}


# ---------------------------------------------------------------------------
# REGRESSION TESTS — these must reproduce the workbook exactly
# ---------------------------------------------------------------------------

def _assert_close(actual, expected, label, tol=1e-6):
    assert abs(actual - expected) < tol, f"{label}: got {actual!r}, expected {expected!r}"
    print(f"  pass  {label:<34} {actual:,.6f}")


def _run_tests():
    print("Reference case: 321 critical CIs, 24x7, Gold, India, EUR 43,856/mo consumption\n")

    ref = Engagement(
        customer="Reference (workbook)",
        inventory={
            "Azure Virtual Machines / Amazon EC2": 15,
            "App Service / AWS Elastic Beanstalk": 260,
            "Azure Kubernetes Service (AKS) / Amazon EKS": 46,
        },
        monthly_consumption_eur=43_856.0,
        coverage="24x7",
        support_model="Gold",
        location="India",
    )
    q = quote(ref)

    _assert_close(unit_price("Azure Virtual Machines / Amazon EC2", "24x7", "Gold"),
                  18.502633102565962, "unit price, VM 24x7 Gold")
    _assert_close(unit_price("Azure Kubernetes Service (AKS) / Amazon EKS", "24x7", "Gold"),
                  77.09430459402485, "unit price, AKS 24x7 Gold")
    _assert_close(q.service_cost_eur, 8634.562114530783, "service cost")
    _assert_close(q.base_pack_eur, 2863.9519999999998, "base pack (24x7 uplift)", tol=1e-4)
    _assert_close(q.cloud_services_cost_eur, 11498.514114530783, "cloud services cost", tol=1e-4)
    _assert_close(q.platform_cost_eur, 5597.304, "platform cost", tol=1e-4)
    _assert_close(q.total_monthly_eur, 17095.818114530783, "monthly recurring price", tol=1e-4)
    _assert_close(q.price_per_ci_eur, 53.258000356793715, "price per CI", tol=1e-4)
    _assert_close(q.fte_count, 6.4348664156948585, "implied FTE", tol=1e-6)
    assert q.slab == "301 - 500 CIs", q.slab
    print(f"  pass  {'slab':<34} {q.slab}")
    assert q.transition_weeks == 12
    print(f"  pass  {'transition weeks':<34} {q.transition_weeks}")

    print("\n  Implied team:")
    for role, n in q.team.items():
        print(f"      {role:<30} {n}")

    print("\nMargin check against a SOW value:")
    ref.sow_monthly_revenue_eur = 17_095.82
    m = margin(ref, q)
    print(f"  revenue        EUR {m.revenue_eur:,.2f}")
    print(f"  modelled cost  EUR {m.modelled_cost_eur:,.2f}")
    print(f"  gross margin       {m.gross_margin_pct:.2%}  ({m.health})")

    print("\n  With 1,100 actual effort hours from ServiceNow:")
    m2 = margin(ref, q, actual_effort_hours=1100)
    print(f"  actual cost    EUR {m2.actual_cost_eur:,.2f}")
    print(f"  variance       EUR {m2.variance_vs_model_eur:,.2f}")
    print(f"  gross margin       {m2.gross_margin_pct:.2%}  ({m2.health})")

    print("\n  Slab headroom:", slab_headroom(321))
    print("\nAll regression tests passed.")


if __name__ == "__main__":
    _run_tests()
