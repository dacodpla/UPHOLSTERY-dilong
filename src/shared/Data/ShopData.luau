-- ============================================================
--  ShopProducts.lua
--  ModuleScript — ReplicatedStorage/Data/ShopProducts
--  UPHOLSTERY! — v7.0 Compatible
--
--  Berisi data dummy untuk semua produk yang bisa dibeli
--  menggunakan in-game Coins (bukan Robux).
--
--  Struktur per produk:
--    id          : string  — unique key, dipakai DataStore & logic
--    name        : string  — display name di UI
--    description : string  — tooltip / deskripsi singkat
--    category    : string  — "Tool" | "JobManagement" | "Efficiency" | "Reputation"
--    price       : number  — harga dalam Coins
--    icon        : string  — rbxassetid placeholder (ganti di Creator Hub)
--    effect      : table   — data efek yang dibaca oleh sistem terkait
--    oneTimeUse  : bool    — true = habis setelah dipakai (consumable)
--    requiresTier: string? — nil = semua tier bisa beli; atau "Mid"/"Premium"/"Prestige"
--    unlockedBy  : string? — nil = langsung tersedia; atau id Story Job / milestone
-- ============================================================

local ShopProducts = {}

-- ─────────────────────────────────────────────
--  KATEGORI 1 — TOOL UPGRADES
--  Memperlebar tolerance / mempercepat minigame.
--  Sesuai GDD: tidak boleh memberikan stat advantage
--  besar — hanya QoL dan pengurangan frustrasi.
-- ─────────────────────────────────────────────
ShopProducts.Tools = {

    {
        id              = "tool_curved_needle",
        name            = "Curved Needle",
        description     = "Memperlebar toleransi jalur di minigame Seam Stitching. "
                       .. "Sedikit lebih memaafkan saat tangan bergerak cepat.",
        category        = "Tool",
        price           = 500,
        icon            = "rbxassetid://0000000001",   -- ganti dengan assetId asli
        oneTimeUse      = false,
        requiresTier    = nil,
        unlockedBy      = nil,
        effect = {
            targetMinigame  = "SeamStitching",
            toleranceBonus  = 0.20,    -- +20% lebar jalur toleransi
        },
    },

    {
        id              = "tool_foam_press_kit",
        name            = "Foam Press Kit",
        description     = "Set penjepit busa yang memudahkan penempatan potongan foam "
                       .. "di minigame Foam Padding. Rotasi terasa lebih presisi.",
        category        = "Tool",
        price           = 800,
        icon            = "rbxassetid://0000000002",
        oneTimeUse      = false,
        requiresTier    = nil,
        unlockedBy      = nil,
        effect = {
            targetMinigame  = "FoamPadding",
            toleranceBonus  = 0.20,    -- +20% snap tolerance saat drag & rotate
        },
    },

    {
        id              = "tool_speed_stapler",
        name            = "Speed Stapler",
        description     = "Staple gun ergonomis yang mempersingkat durasi bar di "
                       .. "minigame Staple Gunning. Lebih sedikit ketukan, hasil sama.",
        category        = "Tool",
        price           = 650,
        icon            = "rbxassetid://0000000003",
        oneTimeUse      = false,
        requiresTier    = nil,
        unlockedBy      = nil,
        effect = {
            targetMinigame  = "StapleGunning",
            durationReduction = 0.15,  -- bar bergerak 15% lebih lambat (lebih mudah)
        },
    },

    {
        id              = "tool_grip_gloves",
        name            = "Grip Gloves",
        description     = "Sarung tangan anti-slip yang menstabilkan input drag "
                       .. "di Foam Padding. Mengurangi efek jitter pada layar sentuh.",
        category        = "Tool",
        price           = 400,
        icon            = "rbxassetid://0000000004",
        oneTimeUse      = false,
        requiresTier    = nil,
        unlockedBy      = nil,
        effect = {
            targetMinigame  = "FoamPadding",
            jitterReduction = 0.30,    -- filter 30% noise pada input drag
        },
    },

    {
        id              = "tool_needle_threader",
        name            = "Needle Threader",
        description     = "Alat bantu yang menempatkan jarum otomatis di titik awal "
                       .. "yang optimal saat Seam Stitching dimulai. Hemat waktu setup.",
        category        = "Tool",
        price           = 300,
        icon            = "rbxassetid://0000000005",
        oneTimeUse      = false,
        requiresTier    = nil,
        unlockedBy      = nil,
        effect = {
            targetMinigame  = "SeamStitching",
            autoSnapToStart = true,    -- cursor mulai tepat di titik awal jalur
        },
    },

    {
        id              = "tool_professional_shears",
        name            = "Professional Shears",
        description     = "Gunting profesional yang diperlukan untuk minigame "
                       .. "Fabric Cutting (Update 1). Wajib dimiliki untuk job Premium ke atas.",
        category        = "Tool",
        price           = 1200,
        icon            = "rbxassetid://0000000006",
        oneTimeUse      = false,
        requiresTier    = "Premium",
        unlockedBy      = "update_1_launch",   -- tersedia saat Update 1 dirilis
        effect = {
            targetMinigame  = "FabricCutting",
            unlocks         = true,            -- tanpa ini minigame tidak bisa dimulai
        },
    },

    -- ── Bolt-tier perk charges (charge-based, equippable in Toolbox) ──────────

    {
        id          = "tack_magnet_bolt",
        name        = "Tack Magnet",
        grade       = "Bolt",
        description = "Approach window +0.6 s — more time to click each tack.",
        category    = "Tool",
        minigame    = "TackRemoval",
        price       = 250,
        icon        = "rbxassetid://0000000020",
        oneTimeUse  = true,
        effect = { approachTimeBonus = 0.6 },
    },

    {
        id          = "sharp_eye_bolt",
        name        = "Sharp Eye",
        grade       = "Bolt",
        description = "Perfect threshold –8 % — easier to land a clean strike.",
        category    = "Tool",
        minigame    = "TackRemoval",
        price       = 220,
        icon        = "rbxassetid://0000000021",
        oneTimeUse  = true,
        effect = { perfectMinProgressReduction = 0.08 },
    },

    {
        id          = "staple_guide_bolt",
        name        = "Staple Guide",
        grade       = "Bolt",
        description = "Both landing zones 35 % wider — forgiving on fast triggers.",
        category    = "Tool",
        minigame    = "StapleGunning",
        price       = 300,
        icon        = "rbxassetid://0000000022",
        oneTimeUse  = true,
        effect = { zoneWidthMultiplier = 1.35 },
    },

    {
        id          = "grip_wrap_bolt",
        name        = "Grip Wrap",
        grade       = "Bolt",
        description = "Bar speed –0.12 — a calmer pace through every staple.",
        category    = "Tool",
        minigame    = "StapleGunning",
        price       = 240,
        icon        = "rbxassetid://0000000023",
        oneTimeUse  = true,
        effect = { barSpeedReduction = 0.12 },
    },

    {
        id          = "curved_needle_bolt",
        name        = "Curved Needle",
        grade       = "Bolt",
        description = "Deviation tolerance +25 % — the seam path forgives small drifts.",
        category    = "Tool",
        minigame    = "SeamStitching",
        price       = 300,
        icon        = "rbxassetid://0000000024",
        oneTimeUse  = true,
        effect = { deviationToleranceBonus = 0.25 },
    },

    {
        id          = "linen_thread_bolt",
        name        = "Linen Thread",
        grade       = "Bolt",
        description = "Miss budget +0.8 s — a little breathing room before a stitch fails.",
        category    = "Tool",
        minigame    = "SeamStitching",
        price       = 200,
        icon        = "rbxassetid://0000000025",
        oneTimeUse  = true,
        effect = { missBudgetBonus = 0.8 },
    },

    {
        id          = "foam_press_kit_bolt",
        name        = "Foam Press Kit",
        grade       = "Bolt",
        description = "One fewer foam piece — a lighter workload this job.",
        category    = "Tool",
        minigame    = "FoamPadding",
        price       = 350,
        icon        = "rbxassetid://0000000026",
        oneTimeUse  = true,
        effect = { pieceCountReduction = 1 },
    },

    {
        id          = "layout_pins_bolt",
        name        = "Layout Pins",
        grade       = "Bolt",
        description = "Time limit +15 s — pin the layout down and work at your own pace.",
        category    = "Tool",
        minigame    = "FoamPadding",
        price       = 250,
        icon        = "rbxassetid://0000000027",
        oneTimeUse  = true,
        effect = { timeLimitBonus = 15 },
    },

}

-- ─────────────────────────────────────────────
--  KATEGORI 2 — JOB MANAGEMENT
--  Membantu pemain mengelola job board yang kompetitif.
--  Efek berupa informational advantage ringan —
--  tidak menggandakan pay atau follower.
-- ─────────────────────────────────────────────
ShopProducts.JobManagement = {

    {
        id              = "job_alert_ping",
        name            = "Job Alert Ping",
        description     = "Aktifkan notifikasi di HP in-game saat Hot Job muncul di board, "
                       .. "0.5 detik sebelum animasi border-nya selesai. Aktif 24 jam.",
        category        = "JobManagement",
        price           = 200,
        icon            = "rbxassetid://0000000007",
        oneTimeUse      = false,
        requiresTier    = nil,
        unlockedBy      = nil,
        effect = {
            notifyOnHotJob      = true,
            notifyLeadTimeMs    = 500,     -- notif 500ms lebih awal dari animasi selesai
            durationHours       = 24,
        },
    },

    {
        id              = "job_deadline_extension",
        name            = "Deadline Extension Token",
        description     = "Tambahkan 30 detik pada job bertipe Urgent. "
                       .. "Sekali pakai — gunakan dengan bijak.",
        category        = "JobManagement",
        price           = 350,
        icon            = "rbxassetid://0000000008",
        oneTimeUse      = true,            -- consumable
        requiresTier    = nil,
        unlockedBy      = nil,
        effect = {
            deadlineExtensionSeconds = 30,
            appliesToModifier        = "Urgent",
        },
    },

    {
        id              = "job_reroll",
        name            = "Job Re-Roll",
        description     = "Kembalikan 1 job yang sudah kamu klaim ke pool tanpa "
                       .. "penalti reputasi. Berguna kalau salah klaim job yang terlalu sulit.",
        category        = "JobManagement",
        price           = 150,
        icon            = "rbxassetid://0000000009",
        oneTimeUse      = true,            -- consumable
        requiresTier    = nil,
        unlockedBy      = nil,
        effect = {
            returnJobToPool     = true,
            reputationPenalty   = 0,       -- override penalti abandon normal (−1.5)
        },
    },

    {
        id              = "job_sticky_note",
        name            = "Sticky Notes",
        description     = "Tandai 1 job di board sebagai 'watching'. "
                       .. "Dapat notifikasi jika job tersebut hampir expire atau hampir diambil orang lain.",
        category        = "JobManagement",
        price           = 180,
        icon            = "rbxassetid://0000000010",
        oneTimeUse      = false,
        requiresTier    = nil,
        unlockedBy      = nil,
        effect = {
            watchSlots              = 1,   -- jumlah job yang bisa di-watch sekaligus
            notifyOnNearExpiry      = true,
            notifyOnNearClaim       = true,
            nearExpiryThresholdSec  = 15,
        },
    },

}

-- ─────────────────────────────────────────────
--  KATEGORI 3 — EFFICIENCY & COMFORT
--  QoL murni. Tidak ada gameplay advantage langsung.
--  Sesuai design pillar "chill game" di GDD.
-- ─────────────────────────────────────────────
ShopProducts.Efficiency = {

    {
        id              = "eff_tool_pouch",
        name            = "Tool Pouch",
        description     = "Tas alat terorganisir yang mempersingkat animasi 'ambil tool' "
                       .. "sebelum minigame dimulai. Kecil tapi terasa.",
        category        = "Efficiency",
        price           = 700,
        icon            = "rbxassetid://0000000011",
        oneTimeUse      = false,
        requiresTier    = nil,
        unlockedBy      = nil,
        effect = {
            toolPickupAnimationReduction = 0.40,  -- animasi 40% lebih cepat
        },
    },

    {
        id              = "eff_work_playlist",
        name            = "Work Playlist",
        description     = "Aktifkan playlist musik lo-fi khusus UPHOLSTERY! "
                       .. "selama kamu di lokasi klien. Murni kosmetik — tapi bikin mood.",
        category        = "Efficiency",
        price           = 250,
        icon            = "rbxassetid://0000000012",
        oneTimeUse      = false,
        requiresTier    = nil,
        unlockedBy      = nil,
        effect = {
            cosmetic        = true,
            ambientMusicId  = "rbxassetid://0000000099",  -- upload track di Creator Hub
        },
    },

    {
        id              = "eff_rush_delivery_coins",
        name            = "Rush Delivery (Coins)",
        description     = "Skip timer pengiriman tool ke lokasi klien. "
                       .. "Versi coins lebih mahal dari versi Robux — tapi tidak perlu Robux.",
        category        = "Efficiency",
        price           = 400,              -- lebih mahal dari versi Robux (R$15 ≈ ~150 coins eq)
        icon            = "rbxassetid://0000000013",
        oneTimeUse      = true,
        requiresTier    = nil,
        unlockedBy      = nil,
        effect = {
            skipToolDeliveryTimer = true,
        },
    },

}

-- ─────────────────────────────────────────────
--  KATEGORI 4 — REPUTASI & KLIEN
--  Membantu menjaga hubungan dengan klien.
--  Tidak menggantikan skill — hanya mengurangi punishment.
-- ─────────────────────────────────────────────
ShopProducts.Reputation = {

    {
        id              = "rep_apology_note",
        name            = "Apology Note",
        description     = "Kirim surat permintaan maaf ke klien setelah abandon job. "
                       .. "Mengurangi penalti reputasi dari −1.5 menjadi −0.8 bintang.",
        category        = "Reputation",
        price           = 500,
        icon            = "rbxassetid://0000000014",
        oneTimeUse      = true,
        requiresTier    = nil,
        unlockedBy      = nil,
        effect = {
            abandonPenaltyOverride = -0.8,   -- GDD default: -1.5
            appliesToEvent         = "AbandonJob",
        },
    },

    {
        id              = "rep_thank_you_package",
        name            = "Thank You Package",
        description     = "Hadiahkan paket terima kasih ke 1 klien pilihan setelah job selesai. "
                       .. "Bonus +0.25 bintang reputasi untuk klien tersebut.",
        category        = "Reputation",
        price           = 300,
        icon            = "rbxassetid://0000000015",
        oneTimeUse      = true,
        requiresTier    = nil,
        unlockedBy      = nil,
        effect = {
            reputationBonus = 0.25,
            targetClient    = nil,   -- diisi runtime oleh ShopHandler saat pemain memilih klien
        },
    },

}

-- ─────────────────────────────────────────────
--  HELPER: Flat list semua produk (untuk UI search / loop)
-- ─────────────────────────────────────────────
ShopProducts.All = {}
for _, category in pairs({ ShopProducts.Tools, ShopProducts.JobManagement, ShopProducts.Efficiency, ShopProducts.Reputation }) do
    for _, product in ipairs(category) do
        ShopProducts.All[product.id] = product
    end
end

-- ─────────────────────────────────────────────
--  HELPER: Cari produk berdasarkan id
--  Contoh: ShopProducts.GetById("tool_curved_needle")
-- ─────────────────────────────────────────────
function ShopProducts.GetById(id: string)
    return ShopProducts.All[id]
end

-- ─────────────────────────────────────────────
--  HELPER: Ambil semua produk dalam 1 kategori
--  Contoh: ShopProducts.GetByCategory("Tool")
-- ─────────────────────────────────────────────
function ShopProducts.GetByCategory(categoryName: string): { [number]: any }
    local result = {}
    for _, product in pairs(ShopProducts.All) do
        if product.category == categoryName then
            table.insert(result, product)
        end
    end
    return result
end

-- ─────────────────────────────────────────────
--  HELPER: Filter produk berdasarkan tier pemain
--  tierOrder dipakai untuk perbandingan tier
-- ─────────────────────────────────────────────
local tierOrder = { Starter = 1, Mid = 2, Premium = 3, Prestige = 4 }

function ShopProducts.GetAvailableForTier(playerTier: string): { [number]: any }
    local playerLevel = tierOrder[playerTier] or 1
    local result = {}
    for _, product in pairs(ShopProducts.All) do
        local req = product.requiresTier
        if req == nil or (tierOrder[req] and tierOrder[req] <= playerLevel) then
            table.insert(result, product)
        end
    end
    return result
end

return ShopProducts