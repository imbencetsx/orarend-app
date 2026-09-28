import SwiftUI
import AppKit
import Combine
import ServiceManagement

extension Notification.Name {
    static let showSettings = Notification.Name("orarendapp.showSettings")
}

@main
struct OrarendAppMain: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        // Natív Settings scene (⌘, ha az app aktív).
        // A menüből a gomb direktben nyitja (lásd AppDelegate.showSettings).
        Settings {
            SettingsView(clock: delegate.clock, store: delegate.clock.timetableStore)
        }
    }
}

// MARK: - AppDelegate: státuszsor-ikon + popover + settings ablak
// A MenuBarExtra label ignorálja a .bold()/.font()-ot, ezért klasszikus
// NSStatusItem + attributedTitle kell a garantált félkövér felirathoz.

final class AppDelegate: NSObject, NSApplicationDelegate {
    let clock = Clock()

    private var statusItem: NSStatusItem?
    private var popover = NSPopover()
    private var settingsWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Státuszsor-ikon
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.action = #selector(togglePopover(_:))
        item.button?.target = self
        self.statusItem = item

        // Popover a menüvel (Liquid Glass alatt is natív, transient = kívül kattintásra záródik)
        let pop = NSPopover()
        pop.behavior = .transient
        pop.animates = true
        pop.contentSize = NSSize(width: 320, height: 520)
        pop.contentViewController = NSHostingController(rootView: MenuView(clock: clock, store: clock.timetableStore))
        self.popover = pop

        // Félkövér cím követése
        clock.$menuTitle
            .receive(on: RunLoop.main)
            .sink { [weak self] title in self?.updateStatusTitle(title) }
            .store(in: &cancellables)
        updateStatusTitle(clock.menuTitle)

        NotificationCenter.default.addObserver(
            self, selector: #selector(showSettings),
            name: .showSettings, object: nil
        )

        // Ellenőrzéshez / gyors eléréshez: --settings indítási kapcsolóval
        // az app indulás után azonnal felhozza a beállítások ablakot.
        if CommandLine.arguments.contains("--settings") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.showSettings()
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Garantált félkövér + monospaced számok a menüsorban.
    private func updateStatusTitle(_ text: String) {
        guard let button = statusItem?.button else { return }
        let font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        button.attributedTitle = NSAttributedString(string: text, attributes: [
            .font: font
        ])
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            // Fókusz a popoverre, hogy a slider/gombok azonnal működjenek
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    /// Settings megnyitása LSUIElement (dock nélküli) appból megbízhatóan.
    /// Direktben saját NSWindow-t nyitunk (nem a törékeny sendAction-re
    /// hagyatkozunk), ezért mindig feljön.
    @objc func showSettings() {
        popover.performClose(nil)
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 440, height: 480),
                styleMask: [.titled, .closable],
                backing: .buffered, defer: false
            )
            window.title = "OrarendApp beállítások"
            window.center()
            window.isReleasedWhenClosed = false
            self.settingsWindow = window
        }
        // Mindig friss tartalom ugyanazzal a Clock példánnyal
        settingsWindow?.contentViewController = NSHostingController(rootView: SettingsView(clock: clock, store: clock.timetableStore))
        settingsWindow?.makeKeyAndOrderFront(nil)
        settingsWindow?.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Óra + teszt-mód

final class Clock: ObservableObject {
    @Published var now = Date()
    @Published var menuTitle = "…"
    /// Debug mód (Settingsben kapcsolható). Ha false, a teszt-idő UI rejtve marad → clean menü.
    @Published var debugMode: Bool = UserDefaults.standard.bool(forKey: "debugMode") {
        didSet {
            UserDefaults.standard.set(debugMode, forKey: "debugMode")
            // Debug kikapcsolásakor a szimuláció is álljon le.
            if !debugMode && testMode {
                testMode = false
                tick()
            }
        }
    }
    /// Teszt-mód: ha true, nem a valós időt, hanem a szimuláltat mutatja.
    /// Csak debugMode mellett érhető el a UI-ból.
    @Published var testMode = false
    @Published var testWeekday: Int = 2       // 2=Hé … 6=Pé
    @Published var testMinutes: Int = 8 * 60  // éjfél óta perc
    @Published var loginAtStart = SMAppService.mainApp.status == .enabled
    /// JSON-ből töltött órarend + csengetési rend (~/Library/Application Support/… felülírhatja).
    let timetableStore = TimetableStore()

    private var timer: Timer?
    private let cal = Calendar.current
    private var cancellables = Set<AnyCancellable>()

    init() {
        // Órarend-változásra azonnal újraszámolunk.
        timetableStore.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.tick() }
            .store(in: &cancellables)
        // Alap: ha hétvége van, a teszt-nap legyen hétfő, hogy egyből lehessen próbálgatni
        let wd = cal.component(.weekday, from: Date())
        if wd == 1 || wd == 7 { testWeekday = 2; testMinutes = 8 * 60 + 20 }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        tick()
    }

    /// Az idő, ami alapján számolunk (valós vagy szimulált).
    var effectiveDate: Date {
        guard testMode else { return Date() }
        // Mai dátum, de a teszt-hétköznapra és teszt-időre állítva.
        // Egyszerű megközelítés: vedd a mostani hetet, és ugorj a kívánt weekday-re.
        var comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        comps.weekday = testWeekday
        comps.hour = testMinutes / 60
        comps.minute = testMinutes % 60
        comps.second = 0
        return cal.date(from: comps) ?? Date()
    }

    var currentStatus: SchoolStatus {
        status(at: effectiveDate, calendar: cal,
               bellSchedule: timetableStore.bells, timetable: timetableStore.table)
    }

    func tick() {
        now = effectiveDate
        menuTitle = menuBarTitle(for: status(at: now, calendar: cal,
                                             bellSchedule: timetableStore.bells,
                                             timetable: timetableStore.table))
    }

    func toggleLogin() {
        do {
            if loginAtStart {
                try SMAppService.mainApp.unregister()
                loginAtStart = false
            } else {
                try SMAppService.mainApp.register()
                loginAtStart = true
            }
        } catch {
            // pl. sandbox nélkül futtatva debugból: csak visszajelzünk
            loginAtStart = SMAppService.mainApp.status == .enabled
        }
    }
}

// MARK: - Menü nézet (clean, Liquid Glass-barát)

struct MenuView: View {
    @ObservedObject var clock: Clock
    @ObservedObject var store: TimetableStore
    @State private var cal = Calendar.current

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            statusHeader

            Divider()

            todayList

            // Teszt-idő csúszka CSAK debug módban látszik (Settings → Debug mód).
            if clock.debugMode {
                Divider()
                testTimeControls
            }

            Divider()

            footer
        }
        .padding(14)
        .frame(width: 320)
    }

    // MARK: Fejléc: nagy visszaszámlálás — glass kártyában, normál macOS radius-szal
    @ViewBuilder
    private var statusHeader: some View {
        let st = clock.currentStatus
        VStack(alignment: .leading, spacing: 4) {
            Text(headerLine(st))
                .font(.headline)
                .fontWeight(.semibold)
                .lineLimit(2)
            Text(subLine(st))
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func headerLine(_ st: SchoolStatus) -> String {
        switch st {
        case .weekend: return "Hétvége 🎉"
        case .noSchoolToday: return "Ma nincs suli"
        case .afterSchool: return "Tanítás vége 🎉"
        case .beforeSchool(let s, let p, let start, _):
            return "\(p). óra \(BellPeriod.fmt(start))-kor: \(s)"
        case .lesson(let p, let s, let end, _, let next):
            if let n = next { return "\(p). óra: \(s) → köv: \(n)" }
            return "\(p). óra: \(s) (\(BellPeriod.fmt(end))-ig)"
        case .freePeriod(let n, _, _):
            return n.map { "Lyukas óra · köv: \($0)" } ?? "Lyukas óra"
        case .breakTime(let p, let n, let start, _):
            return n.map { "Szünet · \(p). óra \(BellPeriod.fmt(start)): \($0)" }
                ?? "Szünet · \(p). óra \(BellPeriod.fmt(start))"
        }
    }

    private func subLine(_ st: SchoolStatus) -> String {
        switch st {
        case .weekend, .noSchoolToday, .afterSchool:
            return "—"
        case .beforeSchool(_, _, _, let r): return "-\(fullCountdown(r))"
        case .lesson(_, _, _, let r, _): return fullCountdown(r)
        case .freePeriod(_, _, let r): return fullCountdown(r)
        case .breakTime(_, _, _, let r): return fullCountdown(r)
        }
    }

    // MARK: Mai órarend lista — aktív sor pill-szerű kiemeléssel
    @ViewBuilder
    private var todayList: some View {
        let wd = cal.component(.weekday, from: clock.now)
        let dayTable = store.table[wd] ?? [:]
        let st = clock.currentStatus
        let activePeriod: Int? = {
            if case .lesson(let p, _, _, _, _) = st { return p }
            if case .breakTime(let p, _, _, _) = st { return p }
            return nil
        }()
        VStack(alignment: .leading, spacing: 6) {
            Text(dayName(wd) + " · 9B")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            VStack(spacing: 2) {
                ForEach(store.bells, id: \.number) { p in
                    if let subj = dayTable[p.number] {
                        let isActive = activePeriod == p.number
                        HStack(spacing: 8) {
                            Text("\(p.number).")
                                .fontWeight(.semibold)
                                .frame(width: 18, alignment: .trailing)
                            Text("\(p.startLabel)–\(p.endLabel)")
                                .monospacedDigit()
                                .frame(width: 92, alignment: .leading)
                            Text(subj)
                                .fontWeight(isActive ? .semibold : .regular)
                                .lineLimit(1)
                            Spacer()
                            if isActive {
                                Circle()
                                    .fill(Color.accentColor)
                                    .frame(width: 7, height: 7)
                            }
                        }
                        .font(.callout)
                        .foregroundStyle(isActive ? .primary : .secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            isActive ? Color.accentColor.opacity(0.14) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                        )
                    }
                }
            }
            if dayTable.isEmpty {
                Text("Ma nincs tanítás.").font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Teszt-idő (csak debug módban)
    @ViewBuilder
    private var testTimeControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Teszt-idő (szimuláció)", isOn: $clock.testMode)
                .fontWeight(.medium)
                .onChange(of: clock.testMode) { _ in clock.tick() }
            if clock.testMode {
                TestTimeControls(clock: clock)
            }
        }
        .font(.callout)
    }

    @ViewBuilder
    private var footer: some View {
        HStack {
            Button("Beállítások…") {
                NotificationCenter.default.post(name: .showSettings, object: nil)
            }
                .buttonStyle(.link)
            Spacer()
            Button("Kilépés") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.link)
        }
        .font(.callout)
    }

    private func dayName(_ wd: Int) -> String {
        switch wd {
        case 2: return "Hétfő"; case 3: return "Kedd"; case 4: return "Szerda"
        case 5: return "Csütörtök"; case 6: return "Péntek"
        case 1: return "Vasárnap"; default: return "Szombat"
        }
    }
}

// MARK: - Teszt-idő vezérlők (menüben + Settingsben is újrahasználva)

struct TestTimeControls: View {
    @ObservedObject var clock: Clock

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Nap", selection: $clock.testWeekday) {
                Text("Hé").tag(2); Text("Ke").tag(3); Text("Sze").tag(4)
                Text("Cs").tag(5); Text("Pé").tag(6)
            }
            .pickerStyle(.segmented)
            .onChange(of: clock.testWeekday) { _ in clock.tick() }

            HStack {
                Text(String(format: "%d:%02d", clock.testMinutes / 60, clock.testMinutes % 60))
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .frame(width: 48)
                Slider(value: Binding(
                    get: { Double(clock.testMinutes) },
                    set: { clock.testMinutes = Int($0); clock.tick() }
                ), in: Double(7 * 60)...Double(16 * 60), step: 1)
            }
            // Gyorsgombok tipikus határokra
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 52))], spacing: 4) {
                ForEach(["8:10", "9:00", "9:10", "11:50", "12:00", "14:45"], id: \.self) { t in
                    Button(t) {
                        let parts = t.split(separator: ":").compactMap { Int($0) }
                        if parts.count == 2 {
                            clock.testMinutes = parts[0] * 60 + parts[1]
                            clock.tick()
                        }
                    }
                    .buttonStyle(.link)
                    .monospacedDigit()
                }
            }
            .font(.callout)
        }
    }
}

// MARK: - Settings (⌘,)

struct SettingsView: View {
    @ObservedObject var clock: Clock
    @ObservedObject var store: TimetableStore

    var body: some View {
        Form {
            Section("Általános") {
                Toggle("Indítás bejelentkezéskor", isOn: Binding(
                    get: { clock.loginAtStart },
                    set: { _ in clock.toggleLogin() }
                ))
            }

            Section("Órarend (JSON)") {
                if let url = store.sourceURL {
                    Text(url.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                } else {
                    Text("Beépített órarend")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let err = store.errorMessage {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                HStack {
                    Button("Újratöltés") {
                        store.load()
                        clock.tick()
                    }
                    Button("Megnyitás Finderben") {
                        let url = FileManager.default.fileExists(atPath: TimetableStore.userFileURL.path)
                            ? TimetableStore.userFileURL
                            : store.sourceURL
                        if let url {
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        }
                    }
                }
                Text("Szerkeszd a JSON fájlt, majd nyomj Újratöltést.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Fejlesztő") {
                Toggle("Debug mód", isOn: $clock.debugMode)
                Text("Ha be van kapcsolva, a menüben megjelenik a teszt-idő csúszka (nap + idő + gyorsgombok).")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if clock.debugMode {
                    Toggle("Teszt-idő (szimuláció)", isOn: $clock.testMode)
                        .onChange(of: clock.testMode) { _ in clock.tick() }
                    if clock.testMode {
                        TestTimeControls(clock: clock)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 380, height: 420)
        .padding(8)
    }
}
