import SwiftUI

// MARK: - OnboardingView

/// First-launch welcome flow shown once when the app starts for the first time.
/// Four pages guide the user through the key features and let them pick a theme.
///
/// Every page is functional — the theme picker on page 3 genuinely changes the
/// active theme, and the pencil toggle on page 2 persists to AppSettingsStore.
struct OnboardingView: View {
    @EnvironmentObject var themeStore: ThemeStore
    @EnvironmentObject var settingsStore: AppSettingsStore

    @State private var currentPage = 0

    private let pageCount = 4
    private let pageFeedback = UIImpactFeedbackGenerator(style: .light)
    private let selectionFeedback = UISelectionFeedbackGenerator()

    var body: some View {
        ZStack {
            // Background gradient that shifts per page
            backgroundGradient
                .ignoresSafeArea()

            VStack(spacing: 0) {
                TabView(selection: $currentPage) {
                    welcomePage.tag(0)
                    pencilPage.tag(1)
                    themePage.tag(2)
                    readyPage.tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .onChange(of: currentPage) { _, _ in
                    pageFeedback.impactOccurred()
                }

                // Custom page indicator + navigation
                bottomBar
                    .padding(.horizontal, 32)
                    .padding(.bottom, 24)
            }
        }
        .interactiveDismissDisabled()
    }

    // MARK: - Pages

    private var welcomePage: some View {
        VStack(spacing: 24) {
            Spacer()
            OnboardingIconView(systemName: "pencil.and.scribble", isActive: currentPage == 0)
                .accessibilityHidden(true)
            Text("Welcome to Y2Notes")
                .font(.largeTitle.bold())
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Text("A note-taking app built for iPad and Apple Pencil. Write, draw, and study — all in one place.")
                .font(.title3)
                .foregroundStyle(.white.opacity(0.85))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Welcome to Y2Notes. A note-taking app built for iPad and Apple Pencil.")
    }

    private var pencilPage: some View {
        VStack(spacing: 24) {
            Spacer()
            OnboardingIconView(systemName: "applepencil.and.scribble", isActive: currentPage == 1)
                .accessibilityHidden(true)
            Text("Apple Pencil Ready")
                .font(.largeTitle.bold())
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Text("Pressure-sensitive drawing, hover preview, and double-tap to switch tools. Y2Notes is designed for the best Pencil experience.")
                .font(.title3)
                .foregroundStyle(.white.opacity(0.85))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Toggle(isOn: $settingsStore.pencilOnlyDrawing) {
                Label("Pencil-only drawing", systemImage: "pencil.tip")
                    .foregroundStyle(.white)
            }
            .tint(.white.opacity(0.6))
            .padding(.horizontal, 60)
            .padding(.top, 12)
            .accessibilityLabel("Pencil-only drawing. When enabled, finger input pans and zooms instead of drawing.")

            Spacer()
        }
    }

    private var themePage: some View {
        VStack(spacing: 24) {
            Spacer()
            OnboardingIconView(systemName: "paintpalette.fill", isActive: currentPage == 2)
                .accessibilityHidden(true)
            Text("Choose Your Theme")
                .font(.largeTitle.bold())
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Text("Pick a look that suits you. You can always change this later in Settings.")
                .font(.title3)
                .foregroundStyle(.white.opacity(0.85))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 16)], spacing: 16) {
                ForEach(AppTheme.allCases) { theme in
                    themeCard(theme)
                }
            }
            .padding(.horizontal, 40)

            Spacer()
        }
    }

    private var readyPage: some View {
        VStack(spacing: 24) {
            Spacer()
            OnboardingIconView(systemName: "checkmark.seal.fill", isActive: currentPage == 3)
                .accessibilityHidden(true)
            Text("You're All Set")
                .font(.largeTitle.bold())
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Text("Create your first notebook and start writing. Your notes are saved automatically.")
                .font(.title3)
                .foregroundStyle(.white.opacity(0.85))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("You're all set. Create your first notebook and start writing.")
    }

    // MARK: - Components

    private func themeCard(_ theme: AppTheme) -> some View {
        let def = theme.definition
        let isSelected = themeStore.effectiveTheme == theme
        return Button {
            selectionFeedback.selectionChanged()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                themeStore.select(theme)
            }
        } label: {
            VStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(def.canvasBackgroundColor)
                    .frame(height: 50)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(isSelected ? Color.white : Color.clear, lineWidth: 3)
                    )
                    .shadow(color: isSelected ? .white.opacity(0.4) : .clear, radius: 6)
                    .scaleEffect(isSelected ? 1.05 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
                Text(theme.displayName)
                    .font(.caption.bold())
                    .foregroundStyle(.white)
            }
        }
        .accessibilityLabel("\(theme.displayName) theme")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var bottomBar: some View {
        HStack {
            // Skip button (hidden on last page)
            if currentPage < pageCount - 1 {
                Button("Skip") {
                    pageFeedback.impactOccurred()
                    completeOnboarding()
                }
                .foregroundStyle(.white.opacity(0.7))
                .accessibilityLabel("Skip onboarding")
            } else {
                Spacer().frame(width: 60)
            }

            Spacer()

            // Animated pill page dots
            HStack(spacing: 6) {
                ForEach(0..<pageCount, id: \.self) { index in
                    Capsule()
                        .fill(index == currentPage ? Color.white : Color.white.opacity(0.4))
                        .frame(width: index == currentPage ? 20 : 8, height: 8)
                        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: currentPage)
                }
            }
            .accessibilityHidden(true)

            Spacer()

            // Next / Get Started button
            if currentPage < pageCount - 1 {
                Button {
                    pageFeedback.impactOccurred()
                    withAnimation { currentPage += 1 }
                } label: {
                    Text("Next")
                        .bold()
                        .foregroundStyle(.white)
                }
                .accessibilityLabel("Next page")
            } else {
                Button {
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
                    completeOnboarding()
                } label: {
                    Text("Get Started")
                        .bold()
                        .foregroundStyle(.white)
                }
                .accessibilityLabel("Complete onboarding and start using Y2Notes")
            }
        }
    }

    private var backgroundGradient: some View {
        let colors: [Color] = {
            switch currentPage {
            case 0: return [.blue, .indigo]
            case 1: return [.indigo, .purple]
            case 2: return [.purple, .pink]
            default: return [.pink, .orange]
            }
        }()
        return LinearGradient(
            colors: colors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .animation(.easeInOut(duration: 0.4), value: currentPage)
    }

    // MARK: - Actions

    private func completeOnboarding() {
        settingsStore.hasCompletedOnboarding = true
    }
}

// MARK: - Animated onboarding icon

/// Shows a large SF Symbol that bounces in with a spring animation when `isActive` becomes true.
private struct OnboardingIconView: View {
    let systemName: String
    let isActive: Bool

    @State private var appeared = false

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 80))
            .foregroundStyle(.white)
            .scaleEffect(appeared ? 1.0 : 0.4)
            .opacity(appeared ? 1.0 : 0)
            .onChange(of: isActive) { _, active in
                if active {
                    appeared = false
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.65)) {
                        appeared = true
                    }
                }
            }
            .onAppear {
                if isActive {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.65).delay(0.15)) {
                        appeared = true
                    }
                }
            }
    }
}
