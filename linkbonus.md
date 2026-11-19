# LINK BONUS — MEMBER AND ADMIN DASHBOARD DEVELOPMENT PROMPT

## YOUR ROLE

Act as a senior full-stack developer, UI/UX designer, database architect and financial technology engineer.

Develop the complete LINK BONUS Member Dashboard and Admin Dashboard, following the approved visual prototypes and project architecture.

The project must use separate frontend and backend folders:

- `frontend/` — React, TypeScript, Vite and Tailwind CSS.
- `backend/` — Node.js, Express and TypeScript.
- `database/` — Supabase PostgreSQL migrations, schemas and seed data.
- `docs/` — Technical documentation.

Use the existing project structure if already created. Inspect the workspace before modifying anything.

Do not build static dashboard screenshots. Implement real, functional, responsive dashboards connected to the backend.

# 1. DESIGN DIRECTION

Brand: LINK BONUS.

Use the established brand identity:

- Deep navy: #071B3A
- Royal blue: #1769E8
- Turquoise: #16C7C2
- Mint: #DDF8F0
- White: #FFFFFF
- Background: #F5F8FC

The dashboards must look like professional financial technology applications.

Follow the provided LINK BONUS desktop and mobile prototype images as the primary visual references.

Important design rules:

- Keep the interface simple and elegant.
- Use financial amount cards.
- Use readable typography.
- Use consistent spacing.
- Use rounded cards.
- Use attractive but restrained gradients.
- Use Lucide icons.
- Avoid unnecessary information.
- Avoid crowded layouts.
- Avoid excessive charts.
- Make every important button functional.

Build responsive layouts specifically for desktop, tablet and mobile.

# 2. MEMBER DASHBOARD

Create a complete member dashboard with five main navigation sections:

1. Home
2. Invest
3. Wallet
4. Team
5. Profile

On desktop, use a clean sidebar navigation.

On mobile, use a compact header and fixed bottom navigation with the five sections.

## A. MEMBER HOME PAGE

The home page must be focused on financial information.

At the top, display:

- LINK BONUS logo.
- Notification icon.
- User profile avatar.
- User name.
- Account menu.

### Main portfolio card

Create a prominent card showing:

**Total Portfolio Value**

Example display:

$1,250.00

Include a small portfolio performance indicator only when verified performance data is available.

Provide an option to hide or reveal financial amounts.

### Financial amount cards

Create the following cards:

1. Available Balance.
2. Active Investments.
3. Staking Balance.
4. Referral Earnings.

Example design data:

| Card | Illustrative amount |
|---|---:|
| Available Balance | $348.00 |
| Active Investments | $800.00 |
| Staking Balance | $102.00 |
| Referral Earnings | $50.00 |

These amounts are examples for development only.

IMPORTANT:

All amounts must be dynamically retrieved from the authenticated user's actual financial records through secure backend APIs.

Never hardcode these figures into production dashboard components.

Do not count the same funds twice when calculating Total Portfolio Value.

Clearly distinguish between available, invested, staked, pending and withdrawable amounts.

### Main financial actions

Create two prominent buttons:

- Deposit
- Withdraw

Both must open functional workflows.

### Quick Actions

Create simple action cards for:

- Invest
- Exchange
- Stake
- Team
- Profile

Each card must navigate to its corresponding page.

### Recent Transactions

Display a concise list of the latest transactions.

Each transaction should show:

- Transaction type.
- Description.
- Amount.
- Date.
- Status.

Use clear visual distinctions for incoming and outgoing transactions.

Add a View All action leading to transaction history.

Do not add unnecessary promotional sections or excessive information to the member home page.

# 3. INVEST PAGE

Create an investment page with two main tabs:

- Available Plans
- My Investments

Available Plans must display configurable investment plans.

Prepare the ten draft plans:

1. Starter.
2. Basic.
3. Silver.
4. Bronze.
5. Gold.
6. Platinum.
7. Diamond.
8. Premium.
9. Professional.
10. VIP.

Suggested draft amounts:

$10, $25, $50, $100, $250, $500, $1,000, $2,500, $5,000 and $10,000.

These are configurable draft values, not finalized commercial terms.

Each plan must display:

- Plan name.
- Investment amount or range.
- Duration.
- Applicable fees.
- Performance methodology.
- Risk information.
- Investment action.

Do not display guaranteed returns.

My Investments must display:

- Investment amount.
- Investment date.
- Current status.
- Realized profit or loss, where verified.
- Settlement history.
- Investment details.

# 4. WALLET PAGE

Create a clean wallet management interface.

Display:

- Total available wallet balance.
- Supported fiat currencies.
- Supported cryptocurrency balances.
- Deposit action.
- Withdrawal action.
- Exchange action.
- Transaction history.

Initial fiat currencies:

- USD.
- RWF.
- BIF.

Initial crypto assets:

- BTC.
- ETH.
- USDT.
- USDC.

Users must be able to view individual asset balances.

Do not confuse converted display values with actual spendable balances.

Create functional deposit and withdrawal workflows connected to backend services.

# 5. TEAM PAGE — ONE-TIME 50% REFERRAL SYSTEM

Implement ONLY the one-time 50% referral commission model.

The previous three-level referral system is removed.

Do not implement:

- Level 1.
- Level 2.
- Level 3.
- Multi-level commissions.
- Recurring referral commissions.

The only referral commission rule is:

The referrer receives 50% of the invitee's first qualifying investment, credited once only.

Example:

- Invitee's first qualifying investment: $100.
- Commission rate: 50%.
- Referrer commission: $50.
- Invitee's next investment: $200.
- Additional commission: $0.

Display:

- Referral code.
- Referral link.
- Copy link button.
- Total direct referrals.
- Qualifying referrals.
- Total commissions.
- Pending commissions.
- Credited commissions.
- Referral history.

Commission values must come from verified backend records.

Prevent duplicate credits through database constraints, transactional processing and idempotency.

The commission programme must remain disabled for live transactions until its funding source, financial sustainability and legal requirements have been reviewed.

# 6. PROFILE PAGE

Include:

- Personal information.
- Profile image.
- Email and phone number.
- Country.
- Account verification.
- Security settings.
- Password management.
- Two-factor authentication where configured.
- Notification preferences.
- Language settings.
- Support.
- Logout.

# 7. COMPLETE ADMIN DASHBOARD

Create a separate administrative application interface.

The admin dashboard must be fully implemented, not just a visual overview.

Use a professional desktop sidebar and a responsive mobile navigation system.

Admin navigation:

1. Overview.
2. Users.
3. Investments.
4. Transactions.
5. Trading & Staking.
6. Referrals.
7. Reports.
8. Settings.

Use role-based permissions to control access.

# 8. ADMIN OVERVIEW PAGE

Create a professional financial administration dashboard.

At the top display:

- LINK BONUS Admin logo.
- Notifications.
- Administrator profile.
- Account menu.

### Financial statistics cards

Create cards for:

1. Total Registered Users.
2. Verified Users.
3. Active Investments.
4. Total Deposits.
5. Total Withdrawals.
6. Pending Transactions.
7. Active Staking Positions.
8. Referral Commissions.

Example dashboard figures for design and testing:

| Metric | Illustrative value |
|---|---:|
| Total Users | 12,480 |
| Verified Users | 11,230 |
| Active Investments | 2,580 |
| Total Deposits | $2,580,000 |
| Total Withdrawals | $1,740,000 |
| Pending Transactions | 28 |
| Active Staking Positions | 840 |
| Referral Commissions | $125,000 |

These are sample figures only.

All production statistics must be calculated from actual database records.

### Admin overview sections

Include:

- Recent platform activity.
- Recent registrations.
- Recent deposits.
- Recent withdrawals.
- Investment activity.
- Pending approvals.
- System status.
- Important alerts.

Use simple charts only when they provide meaningful information.

Do not overcrowd the overview page.

# 9. ADMIN USER MANAGEMENT

Implement complete user CRUD functionality.

Administrators with the appropriate permissions must be able to:

- Create users.
- View users.
- Edit user details.
- Search users.
- Filter users.
- View user profiles.
- Suspend accounts.
- Reactivate accounts.
- Review verification status.
- Review investment history.
- Review wallet balances.
- Review deposit history.
- Review withdrawal history.
- Review referral information.
- View account activity.

Provide a professional user table with:

- User ID.
- Name.
- Email.
- Country.
- Registration date.
- Verification status.
- Account status.
- Actions.

Create a detailed user profile page.

Financial transactions and completed ledger entries must never be silently deleted or modified through ordinary user management.

All sensitive admin actions must be audited.

# 10. ADMIN INVESTMENT MANAGEMENT

Administrators must be able to:

- Create investment plans.
- Edit investment plans.
- Configure minimum amounts.
- Configure maximum amounts.
- Configure durations.
- Configure applicable fees.
- Activate plans.
- Deactivate plans.
- View active investments.
- Review individual investments.
- Monitor verified performance.
- View settlement records.

Provide filters for:

- Active.
- Completed.
- Pending.
- Suspended.
- Cancelled.

Do not permit administrators to manufacture profits or alter completed financial settlements without auditable correction entries.

# 11. ADMIN TRANSACTION MANAGEMENT

Create a complete transaction administration section.

Tabs:

- All Transactions.
- Deposits.
- Withdrawals.
- Pending.
- Completed.
- Failed.
- Reversed.

Display:

- Transaction reference.
- User.
- Transaction type.
- Amount.
- Currency.
- Date.
- Status.
- Provider reference.
- Actions.

Authorized administrators must be able to review and process transactions according to permission policies.

Implement:
- Deposit verification.
- Withdrawal review.
- Approval workflows.
- Rejection with reasons.
- Processing status.
- Provider reconciliation.
- Transaction audit history.

Do not treat screenshots or unverified transaction hashes as proof of payment.

# 12. ADMIN TRADING AND STAKING

Create management pages for:

### Trading

- Supported assets.
- Trading pairs.
- Provider connections.
- Exchange fees.
- Orders.
- Trade history.
- Integration status.

### Staking

- Staking products.
- Supported assets.
- Minimum and maximum amounts.
- Locking periods.
- Reward methodology.
- Active positions.
- Completed positions.
- Reward history.
- Unstaking requests.

Use test mode until real provider connections and required approvals are configured.

# 13. ADMIN REFERRAL MANAGEMENT

Implement only the one-time 50% referral system.

Provide:

- Referral programme status.
- Commission rate configuration.
- Total direct referrals.
- Qualifying first investments.
- Pending commissions.
- Credited commissions.
- Commission history.
- Referral relationship details.
- Fraud alerts.
- Reversal records.

Initial commission rate: 50%.

There must be no referral levels and no recurring commissions.

The database must guarantee that each invitee can trigger at most one qualifying referral commission.

Provide an enable/disable control for authorized administrators.

Do not allow live activation until financial sustainability and legal reviews are completed.

# 14. ADMIN REPORTS

Create reporting pages for:

- User registrations.
- User verification.
- Deposits.
- Withdrawals.
- Investments.
- Verified performance.
- Staking.
- Trading.
- Referral commissions.
- Financial ledger.
- System activity.

Include date filters and export options where appropriate.

Reports must be generated from real database information.

# 15. ADMIN SETTINGS

Create organized settings sections:

- General platform settings.
- User management settings.
- Supported currencies.
- Supported crypto assets.
- Investment settings.
- Staking settings.
- Exchange settings.
- Transaction fees.
- Referral programme settings.
- Notifications.
- Admin roles and permissions.
- Security settings.
- Maintenance mode.

Sensitive settings must require appropriate administrator permissions.

Maintain an audit trail of configuration changes.

# 16. DATABASE AND BACKEND CONNECTION

Use Supabase PostgreSQL as the main database.

Implement secure backend APIs for all dashboard functionality.

The backend must provide endpoints for:

- Member dashboard statistics.
- Member portfolio.
- Member transactions.
- Investments.
- Wallet balances.
- Deposits.
- Withdrawals.
- Staking.
- Referrals.
- User profiles.
- Admin overview statistics.
- Admin user management.
- Admin investment management.
- Admin transaction management.
- Admin referral management.
- Reports.
- Settings.

All financial information must be retrieved through authenticated and authorized backend requests.

Apply appropriate database Row Level Security.

Members must only access their own private financial information.

Administrators must only access functions permitted by their assigned roles.

Never expose database passwords, service-role keys or private provider credentials in frontend code.

# 17. FINANCIAL INTEGRITY

Use double-entry accounting.

All balance-changing operations must generate ledger entries.

Use exact decimal or integer-based monetary representations.

Do not use JavaScript floating-point arithmetic for financial calculations.

Protect all financial operations against:

- Duplicate requests.
- Concurrent processing.
- Unauthorized access.
- Insufficient balances.
- Invalid currencies.
- Repeated settlement jobs.

Use idempotency keys and database constraints.

Do not generate artificial investment profits.

Automatic settlement must use verified attributable performance data.

# 18. MOBILE RESPONSIVENESS

This requirement is extremely important.

The member and admin dashboards must work properly on mobile phones.

Member mobile navigation:

- Home.
- Invest.
- Wallet.
- Team.
- Profile.

Mobile member home must show the portfolio card and financial amount cards clearly.

Use two-column cards when screen width permits, otherwise stack them.

Deposit and Withdraw must remain easy to access.

Recent transactions must be readable without horizontal scrolling.

Admin mobile interface must allow administrators to:
- View important statistics.
- Search users.
- Review transactions.
- Review pending approvals.
- Manage investments.
- Review referral activity.

Use responsive tables, mobile-friendly record cards and collapsible navigation.

Do not simply shrink the desktop sidebar and tables.

# 19. FUNCTIONAL REQUIREMENTS

Every visible button must have a meaningful action.

Do not leave:
- Dead buttons.
- Fake links.
- Non-functional menus.
- Decorative forms.
- Hardcoded financial statistics.
- Fake successful deposits.
- Fake withdrawals.
- Fake referral credits.

Where a provider integration is unavailable, display an honest TEST MODE or NOT CONFIGURED status.

Use clearly identified seed data for development and never mix demo data with production financial records.

# 20. TESTING

Create tests for:

- Member authentication.
- Admin authentication.
- Role permissions.
- Member data isolation.
- Dashboard statistics.
- User CRUD.
- Investment management.
- Deposit processing.
- Withdrawal processing.
- Staking.
- Referral commission calculation.
- One-time commission enforcement.
- Duplicate transaction prevention.
- Ledger consistency.
- Responsive layouts.

Verify that the same invitee cannot trigger more than one referral commission.

Verify that a second investment generates no additional referral commission.

Run tests and fix errors.

# 21. EXECUTION INSTRUCTIONS

First inspect the existing project.

Then implement the dashboards in the following order:

1. Establish the shared design system.
2. Implement the responsive member dashboard.
3. Implement the complete responsive admin dashboard.
4. Connect member dashboard data to backend APIs.
5. Connect admin dashboard data to backend APIs.
6. Implement role-based authorization.
7. Implement user management.
8. Implement investment management.
9. Implement transaction management.
10. Implement staking and exchange management.
11. Implement the one-time referral management system.
12. Implement reports and settings.
13. Run tests.
14. Fix all detected errors.
15. Update project documentation.

Do not stop after creating visual layouts.

Deliver functional pages, reusable components, secure APIs, database migrations and tests.

After completing development, provide a report showing:

- Pages implemented.
- Backend endpoints created.
- Database tables and migrations.
- Admin permissions implemented.
- Member functionality implemented.
- Tests performed.
- Remaining external integrations.
- Exact commands to start frontend and backend.

**FINAL REQUIREMENT: Both dashboards must be fully implemented, responsive, professional and connected to real backend data. Follow the supplied LINK BONUS prototypes, keep the design simple, and preserve the one-time 50% referral commission rule throughout the entire system.**