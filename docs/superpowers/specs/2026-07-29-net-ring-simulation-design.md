# File (Net) Mekaniği — Halka Yığını Modeli

> **Superseded, 2026-07-30.** The ring model this document specifies shipped and
> then proved unable to dent locally: with three degrees of freedom per row, a
> ball pressing from one side could only shrink the whole loop and slide it away,
> which read on screen as the ball passing through the mesh. The net is now a 3D
> woven sheet of 234 knots in `NetClothSimulation.swift`. This document is kept
> as the record of how the cone-of-revolution idea was arrived at — the geometry,
> the hem proportion and the contact philosophy all carried over — but the
> per-row simulation it describes no longer exists.



**Tarih:** 2026-07-29
**Proje:** NotchBasket
**Durum:** Tasarım onaylandı, uygulama planı bekleniyor

## Problem

Mevcut file mekaniği dört ayrı açıdan gerçekçi değil:

1. **File çok sert / az oynuyor** — kafes gibi duruyor, kumaş gibi değil.
2. **Top filede tuhaf davranıyor** — görünmez bir duvara çarpıyor, hareketi fileden bağımsız hissettiriyor.
3. **File şekli bozuluyor** — düğümler birbirine giriyor, ipler kesişiyor.
4. **Zamanlama yapay** — sayı anında her yer aynı anda oynuyor, dalga yayılmıyor.

### Kök neden

File **iki kez, birbirinden habersiz** simüle ediliyor:

| Katman | Konum | Görevi |
|---|---|---|
| `NetClothSimulation` | `NotchBasket/Nodes/HoopNode.swift:587` | 121 düğümlü Verlet kumaş — yalnızca görsel |
| `NetFunnelGuide` | `NotchBasket/Nodes/HoopNode.swift:468` | Topun konumunu/hızını elle huniye zorlar |
| `applySwishImpulse` | `NotchBasket/Nodes/HoopNode.swift:674` | Sayı anında tüm ipliklere toplu darbe |

Sonuç: top aslında fileye çarpmıyor, görünmez bir koniye çarpıyor; file de ayrıca "çarpmış gibi" oynuyor. Filenin şişmesi ile topun yavaşlaması **aynı olaydan doğmuyor**.

İki spesifik kusur:

- `BasketballScene.swift:407` — `ball.position` fizik adımından önce elle atanıyor. Bu ışınlama, "görünmez duvar" hissinin doğrudan kaynağı.
- `NetFunnelGuide` frenlemeyi `pow(0.993, frameScale)` katsayısıyla yapıyor — fiziksel karşılığı olmayan uydurma bir sönüm.

## Çözüm

Fileyi 2B bez olarak değil, gerçekte olduğu gibi **dönel bir koni** olarak modelle. Simülasyonu göründüğü şey üzerinde değil, davrandığı şey üzerinde kur; görünümü ondan türet.

### Serbestlik derecesi karşılaştırması

| Model | DOF | Dolanma riski |
|---|---|---|
| Mevcut kumaş | 121 parçacık × 2 = 242, bağımsız | Yapısal olarak mümkün |
| Halka yığını | 11 halka × 3 = 33, hepsi fiziksel | Yapısal olarak imkânsız |

## Mimari

### Bileşen 1 — `NetRingSimulation`

**Yeni dosya:** `NotchBasket/Nodes/NetRingSimulation.swift`
**Bağımlılık:** Yalnızca `CoreGraphics` — SpriteKit yok, tam test edilebilir.

File 11 halkadan oluşur (`ringCount = 11`, indeks 0–10). Her halkanın 3 serbestlik derecesi vardır:

| DOF | Anlamı | Yay sertliği | Dinlenme değeri |
|---|---|---|---|
| `radius` | halkanın gerilmesi | sert (ipler uzamaz) | `lerp(topHalfWidth, bottomHalfWidth, t)` |
| `centerY` | halkanın sarkması | orta | `-depth · t^1.04` |
| `centerX` | yanal savrulma | yumuşak | `0` |

`t = i / (ringCount − 1)`. `topHalfWidth = GameTuning.rimPostOffset − GameTuning.rimPostRadius`, `depth = 76` — ikisi de mevcut değerler.

`bottomHalfWidth` **31'den 22'ye düşürülür.** Eski kumaş modelindeki 31, topun 24 birimlik yarıçapından geniş: tam ortadan giren bir top filenin boyunca hiçbir ipe değmeden düşebiliyordu, yani temiz swish'te file hiç şişmiyordu. Gerçek filenin ağzı toptan dardır ve top tarafından gerilmek zorundadır — swish dediğimiz şey zaten o gerilmedir. Bu, "file çok sert / az oynuyor" şikâyetinin ölçülebilir kısmının doğrudan sebebi. 22, NBA oranını da tutturur: gerçek hem topun ~0.96'sı, 22 ile 0.92.

Bunun bir sonucu var: her halka toptan geniş olduğu için **tam ortadan geçen top yalnızca hem'e değer**. Gerçek filede de böyledir, ama testlerin temas koordinatları bu dar pencereye (`hypot(22, y+76) < 24`, yani `y ∈ (−85.6, −66.4)`) göre seçilmek zorunda.

Halka 0 çembere sabittir (pinned): üç DOF'u da dinlenme değerinde kilitli.

**Kuvvetler:**

1. **Geri çağırma** — her DOF kendi dinlenme değerine yaylanır.
2. **Komşu halka bağı** — işin kalbi. İpler uzamaz: bir halka topla genişlerse ipin boyu bir yerden gelmek zorunda, dolayısıyla alttaki halka yukarı ve içeri çekilir. Gerçek filenin topu kavrayıp sonra fırlatmasının sebebi budur. Ardışık halkalar arasındaki ip uzunluğu `√(Δy² + Δr²)` dinlenme değerine yaylanır.
3. **Yerçekimi** — `centerY` üzerinde küçük sabit aşağı bileşen.
4. **Sönüm** — hız orantılı, kritik altı (salınım korunur, "whip" hissi bundan gelir).

### Bileşen 2 — Top ↔ file bağlantısı (iki yönlü)

Her halka 3B'de yatay düzlemde bir çemberdir: merkez `(centerXᵢ, yᵢ, 0)`, yarıçap `radiusᵢ`. Top 2B oyun düzleminde hareket ettiğinden `bz = 0`.

Temas testi — **top merkezinin çembere en yakın noktaya uzaklığı**:

```
ρ = |bx − centerXᵢ|                          // eksenden yatay uzaklık
d = √( (ρ − radiusᵢ)² + (by − yᵢ)² )         // ipe uzaklık
girinti = max(R − d, 0)
n̂ = normalize( sign(bx − centerXᵢ)·(ρ − radiusᵢ),  by − yᵢ )
```

Bu tek formül bütün durumları kapsar: top file **içinde**, **dışında**, **üstünde** veya **altında**. Alttan gelen top hem'i yukarı iter; yandan sıyıran top halkayı içeri büker.

**Koni frenlemesi bu formülden türer.** Aşağı doğru daralan halka yığını üzerinde girintilerin bileşkesi kendiliğinden yukarı bakar. `dr/dy` terimini elle yazmaya gerek yoktur. Tam ortadan geçen swish az frenlenir, kenardan giren top çok — özel durum kodu olmadan.

**Etki, eşit ve zıt:**

- Halkaya: `radiusᵢ`, `centerXᵢ`, `yᵢ` girintinin **tersi** yönde itilir — içerideki top halkayı açar, dışarıdaki top sıkar.
- Topa: aynı büyüklükte kuvvet, `n̂` yönünde.

**Eksen simetrisi.** Yatay bileşenler `axialFraction = |bx − centerXᵢ| / radiusᵢ` ile ölçeklenir. Tam eksende duran topu halka her yönden eşit sıkıştırır, yanal bileşenler birbirini götürür; bu çarpan olmadan radyal yön eksende tanımsız kalır ve kusursuz bir swish yana tekme yer.

Toplam kuvvet `SKPhysicsBody.applyForce` ile gerçek fizik gövdesine verilir. `ball.position` **hiçbir zaman** elle atanmaz (aşağıdaki sayısal emniyet hariç).

**Silinen davranışlar:**

- `NetFunnelGuide` tamamen kaldırılır. Yerine yalnızca sayısal emniyet: çok hızlı topun ipler arasından tünellemesini önleyen, kare başına en fazla **2px** yanal düzeltme — `didSimulatePhysics()` içinde uygulanır, entegratörle kavga etmez.
- `applySwishImpulse` tamamen kaldırılır. Dalga halkadan halkaya kendiliğinden yayılır; sayı anında ayrı animasyon tetiklenmez. `playScoreAnimation` yalnızca çember flaşını korur.

### Bileşen 3 — Çizim

`NetMeshNode.render()` yeniden yazılır. Görsel halkalardan **türetilir**, ayrı durum tutmaz.

Her halkada `cordCount = 10` ip düğümü, açı `θⱼ = 2πj/cordCount + twistᵢ`:

```
x = centerXᵢ + radiusᵢ · cos(θ)
y = centerYᵢ + k · radiusᵢ · sin(θ)
derinlik = sin(θ)                    // +1 arka, −1 ön
```

`k = (SideHoopLayout.rimDepth / 2) / topHalfWidth ≈ 0.093` — çemberin izdüşüm oranı. Çember ve file aynı sabitten türediği için tutarlı kalırlar.

`twistᵢ = t · 0.12 rad` — ipin sarmal duruşu.

Elmas doku `(i,j) → (i+1, j±1)` iplerinden oluşur. Her ip, **uç noktalarının ortalama derinliğine göre** ön veya arka katmana yazılır. Örgü artık taklit değil, gerçek 3B dokunun izdüşümü: top içeri girdiğinde önünde kalan ipler kendiliğinden doğru olanlardır.

Alt kenarda hem son halkanın elipsi ve küçük festonlar çizilir.

**Z-sıralaması korunur** (`testBallRendersBetweenRearAndFrontRimLayers` buna bağlı):

| Katman | Yerel z | Efektif z |
|---|---|---|
| `rearOutline` | −1 | 15 |
| `rearMesh` | 0 | 16 |
| **Top** | — | **30** |
| `frontOutline` | 19 | 35 |
| `frontMesh` | 20 | 36 |

### Bileşen 4 — Sahne entegrasyonu

`NotchBasket/Game/BasketballScene.swift`:

```swift
// update(dt) — fizik adımından ÖNCE
let netForce = hoop.updateNet(
    deltaTime: dt,
    ballScenePosition: …,
    ballVelocity: …,
    ballRadius: …,
    reducedEffects: …
)
if ballState == .flying || ballState == .scored {
    ball.physicsBody?.applyForce(netForce)
}

// didSimulatePhysics() — YENİ override, yalnızca sayısal emniyet
if let correction = hoop.netContainmentCorrection(
    ballScenePosition: …,
    ballRadius: …
) {
    ball.position = correction   // ≤ 2px, sadece tünelleme durumunda
}
```

**Kapılama:**

- **Görsel deformasyon:** top var ve `ballState` `.spawning` / `.resetting` değilse **her zaman** çalışır — nişan alırken sürüklenip fileye değse bile file oynar.
- **Kuvvet tepkisi:** yalnızca top dinamikken (`.flying` / `.scored`).
- Sayı olup olmaması **hiçbir yerde koşul değildir.** Potanın altından, yandan veya alttan gelen temaslar da tam olarak aynı yolu kullanır.

`hoop.guideBallThroughNet(…)` ve `hoop.resetNetBallGuide()` kaldırılır; çağrı yerleri (`BasketballScene.swift:248`, `:401`, `:520`) güncellenir.

## Kararlılık ve sınır durumları

| Durum | Önlem |
|---|---|
| Büyük `dt` | `dt` 1/30'a kırpılır (mevcut davranış); halka sim'i 1/240 alt adımlarla koşar |
| Aşırı kuvvet → koni ters döner | `radius` `[bottomHalfWidth · 0.35, topHalfWidth · 1.8]` aralığına kırpılır |
| Halka sırası bozulur | `yᵢ` komşularına göre sıralı kalmaya zorlanır → dolanma yapısal olarak imkânsız |
| Yay patlaması | Topa uygulanan toplam kuvvet üst sınırlı |
| Hızlı top tünellemesi | Alt adımlarda süpürülmüş (swept) temas + 2px'lik emniyet düzeltmesi |
| `ballRadius == 0` veya top yok | Temas hesabı atlanır, file yalnızca dinlenmeye sönümlenir |
| `reducedEffects` | Deformasyon ölçeği kısılır, sönüm artırılır — **ayrı bir animasyon yolu açılmaz** |

## Test planı

**Silinecek:** `NotchBasket/Tests/GeometryTests.swift:241–484` arasındaki 11 file testi (eski modele bağlılar).

**Yeni dosya:** `NotchBasket/Tests/NetSimulationTests.swift`

Taşınan niyetler:

1. `testTopRingStaysPinnedWhileLowerRingsMove`
2. `testBallCannotEscapeThroughNetSide`
3. `testBallIsReleasedAfterClearingBottomOpening`
4. `testFastBallDoesNotTunnelThroughNet`
5. `testNetDampsBackTowardRest`
6. `testRingOrderIsNeverViolated` (eski "düğümler çakışmaz" testinin karşılığı)
7. `testReducedMotionScalesNetResponse`
8. `testBallTouchingNetFromBelowPushesItUpwardWithoutScoring`

Yeni testler:

9. `testNetDeceleratesDescendingBall` — filenin topa gerçekten kuvvet uyguladığını doğrular. **Orijinal hatayı yakalayacak olan test budur**; eski sette karşılığı yoktu.
10. `testDeformationWavePropagatesDownward` — 3. halka 7. halkadan önce deforme olur; scripted swish'in dönmediğinin kanıtı.
11. `testContactAppliesRegardlessOfScoring` — potanın altından ve yandan gelen temasların da kuvvet ürettiğini doğrular.
12. `testCentredBallGetsNoSidewaysKickButOffCentreIsRecentred` — eksen simetrisi çarpanını doğrular.
13. `testDescendingBallStretchesTheHemOpen` — dar ağzın top tarafından gerildiğini, yani swish'in gerçekten oluştuğunu doğrular.

### Neden bu testler

Eski setin 11 testinin hepsi *filenin* davranışını ölçüyordu, hiçbiri *topun fileden ne gördüğünü* ölçmüyordu. Bu yüzden "file oynuyor ama top ondan bağımsız hareket ediyor" hatası testlerden temiz geçebiliyordu. İki yönlü bağlı bir sistemde testin de iki yönü ölçmesi gerekir.

## Kapsam dışı

- Çember, arka pano, montaj donanımı görselleri — dokunulmaz.
- Ses (`AudioService`) — file sesi mevcut haliyle kalır.
- Atış/nişan mekaniği (`ShotController`) — dokunulmaz.
- Skorlama sensörleri — dokunulmaz.

## Değişecek dosyalar

| Dosya | Değişiklik |
|---|---|
| `NotchBasket/Nodes/NetRingSimulation.swift` | **Yeni** — model |
| `NotchBasket/Nodes/HoopNode.swift` | `NetClothSimulation`, `NetFunnelGuide`, `NetParticle`, `NetSpring` silinir; `NetMeshNode.render()` yeniden yazılır; `updateNet` `CGVector` döndürür; `netContainmentCorrection` eklenir; `guideBallThroughNet`/`resetNetBallGuide` kaldırılır |
| `NotchBasket/Game/BasketballScene.swift` | `applyForce` entegrasyonu, `didSimulatePhysics` override, eski çağrıların temizliği |
| `NotchBasket/Tests/GeometryTests.swift` | 11 eski file testi silinir |
| `NotchBasket/Tests/NetSimulationTests.swift` | **Yeni** — 11 test |
| `README.md` | File bölümü (satır 161) yeni modeli anlatacak şekilde güncellenir |
