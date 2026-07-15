import Foundation

// MARK: - Next Action (Etap J)
//
// One unified timeline of "what happens next" in Torn — bars filling, cooldowns ending,
// travel landing, hospital/jail release, education finishing, OC becoming ready, the
// chain timing out, and refills waiting to be claimed. The engine is pure and reads a
// decoupled snapshot of absolute Unix timestamps, so it is fully testable with the
// shared clock and independent of AppState's many models.

enum NextActionCategory: String, CaseIterable, Codable, Sendable {
    case energy, nerve, happy, life
    case drug, medical, booster
    case travel, hospital, jail, education, organizedCrime, chain, refills

    var label: String {
        switch self {
        case .energy: return "Energy full"
        case .nerve: return "Nerve full"
        case .happy: return "Happy full"
        case .life: return "Life full"
        case .drug: return "Drug ready"
        case .medical: return "Medical ready"
        case .booster: return "Booster ready"
        case .travel: return "Landing"
        case .hospital: return "Out of hospital"
        case .jail: return "Out of jail"
        case .education: return "Course complete"
        case .organizedCrime: return "OC ready"
        case .chain: return "Chain timeout"
        case .refills: return "Refills available"
        }
    }

    var systemImage: String {
        switch self {
        case .energy: return "bolt.fill"
        case .nerve: return "brain.head.profile"
        case .happy: return "face.smiling"
        case .life: return "heart.fill"
        case .drug: return "pills.fill"
        case .medical: return "cross.case.fill"
        case .booster: return "testtube.2"
        case .travel: return "airplane.arrival"
        case .hospital: return "cross.fill"
        case .jail: return "lock.fill"
        case .education: return "graduationcap.fill"
        case .organizedCrime: return "person.3.sequence.fill"
        case .chain: return "link"
        case .refills: return "arrow.clockwise.circle.fill"
        }
    }

    /// Stable ordering for tie-breaks when two events share a fire time.
    var order: Int { Self.allCases.firstIndex(of: self) ?? 0 }
}

/// A single upcoming event. `fireAt` is absolute Unix seconds; `eta` is seconds from the
/// snapshot's `now` (never negative).
struct NextEvent: Identifiable, Equatable, Sendable {
    let category: NextActionCategory
    let title: String
    let fireAt: Int
    let eta: Int

    var id: String { category.rawValue }
    var systemImage: String { category.systemImage }
    var isReady: Bool { eta <= 0 }
}

/// Decoupled input the engine turns into a timeline. Absolute Unix timestamps; `nil`
/// means "not applicable / not active".
struct NextActionSnapshot: Equatable {
    var now: Int
    var energyFullAt: Int?
    var nerveFullAt: Int?
    var happyFullAt: Int?
    var lifeFullAt: Int?
    var drugReadyAt: Int?
    var medicalReadyAt: Int?
    var boosterReadyAt: Int?
    var travelArrivalAt: Int?
    var hospitalReleaseAt: Int?
    var jailReleaseAt: Int?
    var educationEndsAt: Int?
    var ocReadyAt: Int?
    var chainTimeoutAt: Int?
    var refillsAvailable: Bool

    init(now: Int) {
        self.now = now
        self.refillsAvailable = false
    }
}

struct NextActionEngine {
    /// Upcoming events, soonest first, excluding hidden categories. Timed events only
    /// appear while still in the future; `refills` appears as a ready (eta 0) state.
    func events(from s: NextActionSnapshot, hidden: Set<NextActionCategory> = []) -> [NextEvent] {
        var out: [NextEvent] = []

        func addFuture(_ category: NextActionCategory, _ at: Int?) {
            guard let at, at > s.now, !hidden.contains(category) else { return }
            out.append(NextEvent(category: category, title: category.label, fireAt: at, eta: at - s.now))
        }

        addFuture(.energy, s.energyFullAt)
        addFuture(.nerve, s.nerveFullAt)
        addFuture(.happy, s.happyFullAt)
        addFuture(.life, s.lifeFullAt)
        addFuture(.drug, s.drugReadyAt)
        addFuture(.medical, s.medicalReadyAt)
        addFuture(.booster, s.boosterReadyAt)
        addFuture(.travel, s.travelArrivalAt)
        addFuture(.hospital, s.hospitalReleaseAt)
        addFuture(.jail, s.jailReleaseAt)
        addFuture(.education, s.educationEndsAt)
        addFuture(.organizedCrime, s.ocReadyAt)
        addFuture(.chain, s.chainTimeoutAt)

        if s.refillsAvailable && !hidden.contains(.refills) {
            out.append(NextEvent(category: .refills, title: NextActionCategory.refills.label, fireAt: s.now, eta: 0))
        }

        return out.sorted {
            $0.fireAt != $1.fireAt ? $0.fireAt < $1.fireAt : $0.category.order < $1.category.order
        }
    }

    /// The single soonest event (what to show on the dashboard / menu bar).
    func nearest(from snapshot: NextActionSnapshot, hidden: Set<NextActionCategory> = []) -> NextEvent? {
        events(from: snapshot, hidden: hidden).first
    }
}
