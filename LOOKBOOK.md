SetAll | Premium Design System & Look Book

🎯 Brand Identity

SetAll is a premium, multi-currency expense engine built for global friends. It is not a playful, cartoonish mobile app; it is a sophisticated, "fintech-grade" tool. The UI should evoke the feeling of high-end desktop apps like Stripe, Linear, or Raycast.

🎨 Color Palette

The app uses a distinct "Teal and Slate" identity.

Dark Theme (Primary)

Deep Slate (App Background): #020617 (Used for the main canvas/content area to provide deep contrast).

Slate Dark (Surfaces/Sidebar): #0F172A (Used for cards, the sidebar, and elevated surfaces).

Brand Teal (Primary Accent): #14B8A6 (Used for primary buttons, active states, and successful balances).

Brand Orange (Warning/Debt): #F97316 (Used for "You Owe" balances or destructive actions).

Glass Border: #FFFFFF at 5% opacity (Used for subtle borders on dark cards to create depth without noise).

Light Theme (Secondary)

Paper White (App Background): #F8FAFC (A very soft, non-toxic, cool-toned white to prevent eye strain).

Pure White (Surfaces): #FFFFFF (Used for cards on top of the Paper White background).

Slate Border: #E2E8F0 (Used for borders on light mode cards).

🔤 Typography (Font: Inter)

Typography must remain sharp and professional.

Display / Hero: 30-32px, FontWeight.bold, Letter Spacing -1.0.

Headers (headlineMedium): 24px, FontWeight.bold, Letter Spacing -0.5.

Card Titles (titleLarge): 18px, FontWeight.w600.

Body Text: 14-16px, FontWeight.normal.

Subtext: 12-13px, Colors: Colors.grey or slate.shade400.

📐 Architecture & Layout Strictness

SetAll uses an AdaptiveShell to prevent desktop UI stretching.

The Cage (Desktop): Main content screens (Dashboard, Groups, Settings) MUST NOT use width: double.infinity. They are constrained by a ConstrainedBox(maxWidth: 780).

The Sidebar (Desktop): A fixed 240px wide navigation rail on the left.

Borders over Shadows: Avoid heavy drop shadows. Prefer a 1px subtle border (Colors.white.withOpacity(0.05)) on cards to define edges.

🧱 Component Rules

Cards: Elevation 0. Border radius 16px. Must have a subtle border.

Primary Buttons (ElevatedButton): Background Teal, Text Deep Slate (Dark Theme). Border radius 12px. Padding vertical 16px. Font weight bold.

Input Fields (TextFormField): Filled background (3% opacity white). No enabled borders. Focused border 2px Teal. Border radius 12px.

Icons: Strictly use lucide_icons. Size is usually 20px for inline, 24px for headers.