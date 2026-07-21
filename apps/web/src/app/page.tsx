import GaussianRoomBackground from "./gaussian-room-background.tsx";

export default function HomePage() {
  return (
    <main className="room-scene" aria-label="Fixed Gaussian room model">
      <GaussianRoomBackground />
    </main>
  );
}
