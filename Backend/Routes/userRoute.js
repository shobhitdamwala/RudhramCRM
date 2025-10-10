import express from "express";
import { deleteTeamMember, getAllTeamMembers, getUserProfile, loginUser, registerUser, updateTeamMember } from "../Controller/userController.js";
import { authenticate, authorize } from "../Middleware/authentication.js";
import upload from "../Middleware/uploadMiddleware.js";

const app = express();


app.post('/register',upload.single("avatar"),registerUser);
app.post('/login',loginUser);
app.get("/me", getUserProfile); 
app.get("/team-members", getAllTeamMembers); 

app.put("/team-members/:id", upload.single("avatar"), updateTeamMember);

app.delete("/team-members/:id", deleteTeamMember);


export default app;