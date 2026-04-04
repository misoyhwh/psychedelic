import RealityKit
import ARKit
import UIKit
import simd

@MainActor
class ParticleSystem {
    let rootEntity = Entity()

    private var particles: [Particle] = []
    private var floorAnchors: [UUID: MeshAnchor] = [:]
    private var sphereMesh: MeshResource?
    private var time: Float = 0
    private let maxParticles = 120
    private var spawnAccumulator: Float = 0

    // Precomputed color materials (reuse to avoid per-frame allocation)
    private var colorMaterials: [UnlitMaterial] = []
    private let colorCount = 32

    // Reusable material for audio-reactive mode (avoids per-particle allocation)
    private var audioReactiveMaterial = UnlitMaterial()

    struct Particle {
        let entity: ModelEntity
        var age: Float = 0
        let lifetime: Float
        var position: SIMD3<Float>
        let velocity: SIMD3<Float>
        let colorPhase: Float
        let pulseSpeed: Float
        let baseScale: Float
        let flashSpeed: Float   // speed of on/off blinking
        let flashSharpness: Float // how sharp the blink is (higher = more on/off)
    }

    init() {
        setupResources()
    }

    private func setupResources() {
        sphereMesh = try? .generateSphere(radius: 0.03)

        // Precompute vivid color materials across the hue spectrum
        for i in 0..<colorCount {
            var material = UnlitMaterial()
            let hue = Float(i) / Float(colorCount)
            // Alternate between full saturation and slightly shifted vibrant colors
            let saturation: Float = (i % 2 == 0) ? 1.0 : 0.85
            let brightness: Float = 1.0
            let color = hsvColor(h: hue, s: saturation, v: brightness, a: 1.0)
            material.color = .init(tint: color)
            material.blending = .transparent(opacity: .init(floatLiteral: 1.0))
            colorMaterials.append(material)
        }
    }

    func updateFloorAnchor(_ anchor: MeshAnchor, event: AnchorUpdate<MeshAnchor>.Event) {
        switch event {
        case .added, .updated:
            if anchor.geometry.classifications != nil {
                floorAnchors[anchor.id] = anchor
            }
        case .removed:
            floorAnchors.removeValue(forKey: anchor.id)
        }
    }

    func update(deltaTime: Float, speed: Float, intensity: Float,
                audioReactive: Bool = false, audioLevel: Float = 0, trebleLevel: Float = 0,
                audioSensitivity: Float = 1.0) {
        time += deltaTime * speed

        // Spawn new particles (audio boosts spawn rate, scaled by sensitivity)
        let audioSpawnBoost: Float = audioReactive ? (1.0 + audioLevel * 3.0 * audioSensitivity) : 1.0
        let spawnRate: Float = 12.0 * intensity * audioSpawnBoost
        spawnAccumulator += deltaTime * spawnRate
        while spawnAccumulator >= 1.0 && particles.count < maxParticles {
            spawnAccumulator -= 1.0
            spawnParticle()
        }

        // Audio-reactive brightness multiplier (sensitivity affects range)
        let brightnessMult: Float = audioReactive ? (0.3 + trebleLevel * 0.7 * audioSensitivity) : 1.0

        // Update existing particles
        var aliveParticles: [Particle] = []
        for var particle in particles {
            particle.age += deltaTime * speed
            if particle.age >= particle.lifetime {
                particle.entity.removeFromParent()
                continue
            }

            // Move upward with slight drift (audio boosts upward speed)
            let audioVelocityBoost: Float = audioReactive ? (1.0 + audioLevel * 1.5 * audioSensitivity) : 1.0
            let drift = SIMD3<Float>(
                sin(time * 2.0 + particle.colorPhase * 10.0) * 0.15,
                0,
                cos(time * 1.5 + particle.colorPhase * 7.0) * 0.15
            )
            particle.position += (particle.velocity * audioVelocityBoost + drift) * deltaTime
            particle.entity.position = particle.position

            // Life ratio for fade in/out
            let lifeRatio = particle.age / particle.lifetime
            let fadeIn = min(lifeRatio / 0.1, 1.0)
            let fadeOut = 1.0 - max((lifeRatio - 0.7) / 0.3, 0.0)
            let alpha = fadeIn * fadeOut

            // Intense flashing: sharp on/off blink pattern
            let rawPulse = sin(time * particle.flashSpeed + particle.colorPhase * .pi * 2.0)
            // Sharpen the pulse: pow makes it snap between on/off
            let sharpPulse = pow(max(rawPulse, 0.0), particle.flashSharpness)
            let pulseAmount: Float = audioReactive ? (0.6 + audioLevel * 2.0 * audioSensitivity) : 1.0
            let scale = particle.baseScale * (0.2 + sharpPulse * 0.8 * pulseAmount) * alpha
            particle.entity.scale = SIMD3<Float>(repeating: max(scale, 0.01))

            // Fast color cycling through vivid hues
            let hueShift = fmod(particle.colorPhase + time * 1.2, 1.0)
            let colorIdx = Int(hueShift * Float(colorCount)) % colorCount

            if audioReactive {
                // Brightness flashes with treble — reuse single material instance
                let flashBright = 0.4 + sharpPulse * 0.6 * brightnessMult
                let baseColor = hsvColor(h: hueShift, s: 1.0, v: flashBright, a: 1.0)
                audioReactiveMaterial.color = .init(tint: baseColor)
                audioReactiveMaterial.blending = .transparent(opacity: .init(floatLiteral: Float(alpha)))
                particle.entity.model?.materials = [audioReactiveMaterial]
            } else {
                particle.entity.model?.materials = [colorMaterials[colorIdx]]
            }

            aliveParticles.append(particle)
        }
        particles = aliveParticles
    }

    private func spawnParticle() {
        guard let mesh = sphereMesh else { return }

        let spawnPos = randomFloorPosition()
        let material = colorMaterials[Int.random(in: 0..<colorCount)]

        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.position = spawnPos
        rootEntity.addChild(entity)

        let particle = Particle(
            entity: entity,
            lifetime: Float.random(in: 2.0...5.0),
            position: spawnPos,
            velocity: SIMD3<Float>(
                Float.random(in: -0.08...0.08),
                Float.random(in: 0.2...0.5),  // upward
                Float.random(in: -0.08...0.08)
            ),
            colorPhase: Float.random(in: 0...1),
            pulseSpeed: Float.random(in: 3.0...8.0),
            baseScale: Float.random(in: 0.8...2.0),
            flashSpeed: Float.random(in: 6.0...18.0),
            flashSharpness: Float.random(in: 1.5...4.0)
        )
        particles.append(particle)
    }

    private func randomFloorPosition() -> SIMD3<Float> {
        // Try to find a floor anchor and pick a random position on it
        if let anchor = floorAnchors.values.randomElement() {
            let geometry = anchor.geometry
            let vertices = geometry.vertices
            let positionData = vertices.buffer.contents()

            // Pick a random vertex from the floor mesh
            if vertices.count > 0 {
                let idx = Int.random(in: 0..<vertices.count)
                let pointer = positionData.advanced(by: vertices.offset + idx * vertices.stride)
                let localPos = pointer.assumingMemoryBound(to: SIMD3<Float>.self).pointee
                // Transform to world space
                let worldPos = anchor.originFromAnchorTransform * SIMD4<Float>(localPos, 1.0)
                return SIMD3<Float>(worldPos.x, worldPos.y, worldPos.z)
            }
        }

        // Fallback: spawn around user's position at approximate floor height
        return SIMD3<Float>(
            Float.random(in: -2.0...2.0),
            -1.0, // approximate floor
            Float.random(in: -2.0...2.0)
        )
    }

    private func hsvColor(h: Float, s: Float, v: Float, a: Float) -> UIColor {
        let c = v * s
        let x = c * (1.0 - abs(fmod(h * 6.0, 2.0) - 1.0))
        let m = v - c
        var r: Float = 0, g: Float = 0, b: Float = 0
        let sector = Int(h * 6.0) % 6
        switch sector {
        case 0: r = c; g = x; b = 0
        case 1: r = x; g = c; b = 0
        case 2: r = 0; g = c; b = x
        case 3: r = 0; g = x; b = c
        case 4: r = x; g = 0; b = c
        default: r = c; g = 0; b = x
        }
        return UIColor(
            red: CGFloat(r + m),
            green: CGFloat(g + m),
            blue: CGFloat(b + m),
            alpha: CGFloat(a)
        )
    }

    func removeAll() {
        for particle in particles {
            particle.entity.removeFromParent()
        }
        particles.removeAll()
    }
}
