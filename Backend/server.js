import express from 'express';
// import bodyParser from 'body-parser';
// import cors from 'cors';
// import mongoose from 'mongoose';
 import dotenv from 'dotenv';
import dbConnection from './Connection/dbConnection.js';
import userRoutes from './Routes/userRoute.js';
import subCompanyRoutes from './Routes/subCompanyRoutes.js';
import leadRoutes from './Routes/leadRoutes.js';
import projectRoutes from './Routes/projectRoutes.js';
import taskRoutes from './Routes/taskRoutes.js';
import meetingRoutes from './Routes/meetingRoutes.js';
import driveRoutes from './Routes/driveFolderRoutes.js';
import clientRoutes from './Routes/clientRoutes.js';
import cookieParser from "cookie-parser";

let app = express();

dotenv.config({ path: './.env/.env' });


app.use(express.json());
app.use(express.urlencoded({ extended: true }));
app.use(cookieParser());

app.use('/api/v1/user',userRoutes);
app.use('/api/v1/subcompany',subCompanyRoutes);
app.use('/api/v1/lead',leadRoutes);
app.use('/api/v1/project',projectRoutes);
app.use('/api/v1/task',taskRoutes);
app.use('/api/v1/meeting',meetingRoutes);
app.use('/api/v1/drive',driveRoutes);
app.use('/api/v1/client',clientRoutes);

app.use("/uploads", express.static("uploads"));


app.listen(process.env.PORT, "0.0.0.0", () => {
  console.log(`✅ Server is running on http://0.0.0.0:${process.env.PORT}`);
});
dbConnection();