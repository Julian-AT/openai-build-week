import ApartmentScene from "./apartment-scene.tsx";

export default function HomePage() {
  return (
    <main className="room-scene" aria-label="Apartment point cloud and labeled 3D model">
      <ApartmentScene />
    </main>
  );
}
